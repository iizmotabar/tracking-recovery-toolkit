-- Finds conversions confirmed in the CRM or call tracking tool that have no
-- matching conversion event in GA4. Each gap here points at a specific broken
-- trigger, a missing tag, or a form/embed that changed without updating tracking.

with confirmed_conversions as (
  -- Pulled from CRM export or call tracking tool: known-good conversions for
  -- the audit window, used as ground truth against GA4's own record.
  select
    lead_id,
    contact_email,
    conversion_timestamp,
    conversion_type,          -- 'form_submit', 'call', 'chat', etc.
    landing_page
  from `project.crm.confirmed_conversions`
  where conversion_timestamp between @start_date and @end_date
),

ga4_conversion_events as (
  select
    user_pseudo_id,
    event_name,
    timestamp_micros(event_timestamp) as event_ts,
    (select value.string_value from unnest(event_params) where key = 'page_location') as page_location
  from `project.analytics_XXXXXXXX.events_*`
  where event_name in ('form_submit', 'generate_lead', 'purchase')
    and _TABLE_SUFFIX between format_date('%Y%m%d', @start_date) and format_date('%Y%m%d', @end_date)
),

matched as (
  select
    c.lead_id,
    c.conversion_type,
    c.landing_page,
    c.conversion_timestamp,
    g.event_name as ga4_matched_event,
    g.event_ts as ga4_event_ts
  from confirmed_conversions c
  left join ga4_conversion_events g
    on c.landing_page = g.page_location
    and abs(timestamp_diff(c.conversion_timestamp, g.event_ts, minute)) <= 5
)

select
  conversion_type,
  landing_page,
  count(*) as confirmed_conversions,
  countif(ga4_matched_event is null) as missing_in_ga4,
  round(countif(ga4_matched_event is null) / count(*) * 100, 1) as pct_missing
from matched
group by conversion_type, landing_page
having missing_in_ga4 > 0
order by pct_missing desc;
