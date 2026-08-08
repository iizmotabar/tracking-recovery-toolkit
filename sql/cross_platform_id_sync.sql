-- Checks whether the same lead has consistent campaign and click IDs across
-- GA4, the ad platform, and the CRM. Divergence here usually means the CRM
-- integration isn't capturing the tracking parameter on lead creation.

with ga4_ids as (
  select
    user_pseudo_id,
    (select value.string_value from unnest(event_params) where key = 'gclid') as ga4_gclid,
    (select value.string_value from unnest(event_params) where key = 'campaign') as ga4_campaign,
    timestamp_micros(event_timestamp) as event_ts
  from `project.analytics_XXXXXXXX.events_*`
  where event_name in ('generate_lead', 'form_submit')
),

crm_ids as (
  select
    lead_id,
    contact_email,
    gclid as crm_gclid,
    utm_campaign as crm_campaign,
    created_at
  from `project.crm.leads`
),

joined as (
  select
    c.lead_id,
    c.crm_gclid,
    g.ga4_gclid,
    c.crm_campaign,
    g.ga4_campaign,
    c.created_at
  from crm_ids c
  left join ga4_ids g
    on abs(timestamp_diff(c.created_at, g.event_ts, minute)) <= 10
)

select
  lead_id,
  crm_gclid,
  ga4_gclid,
  crm_campaign,
  ga4_campaign,
  case
    when ga4_gclid is null then 'no GA4 match found'
    when crm_gclid is null and ga4_gclid is not null then 'CRM never captured the gclid'
    when crm_gclid != ga4_gclid then 'gclid mismatch between platforms'
    when crm_campaign != ga4_campaign then 'campaign name mismatch'
    else 'consistent'
  end as sync_status
from joined
where crm_gclid is null
   or ga4_gclid is null
   or crm_gclid != ga4_gclid
   or coalesce(crm_campaign, '') != coalesce(ga4_campaign, '')
order by created_at desc;
