-- bigquery/ddl/dm/vw_call_driver_regex.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #4
-- Trap: stacked regexp_extract / RLIKE over free-text disposition descriptions.
--
-- Conversion notes:
--   - Hive RLIKE 'pattern' → BigQuery REGEXP_CONTAINS(col, r'pattern').
--   - Hive regexp_extract(str, pattern, group) →
--     BigQuery REGEXP_EXTRACT(str, r'pattern-with-capture-group').
--     BigQuery REGEXP_EXTRACT returns the first capture group by default,
--     so we embed the group into the regex pattern directly.
--   - Hive double-backslash escaping (\\d, \\[) in HQL strings →
--     BigQuery raw string literals r'...' with single backslashes.

CREATE VIEW IF NOT EXISTS dm.vw_call_driver_regex AS
SELECT c.call_date,
       c.queue_id,
       CASE
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(bill|invoice|charge|refund)')    THEN 'BILLING'
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(password|login|locked|reset)')   THEN 'ACCESS'
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(cancel|churn|retention)')        THEN 'RETENTION'
         WHEN REGEXP_EXTRACT(d.disposition_desc, r'^\[([A-Z]{2,5})\]') IS NOT NULL
              THEN REGEXP_EXTRACT(d.disposition_desc, r'^\[([A-Z]{2,5})\]')
         ELSE 'OTHER'
       END                                              AS call_driver,
       REGEXP_EXTRACT(d.disposition_desc, r'ref#(\d+)') AS embedded_ref_no,
       COUNT(*)                                         AS calls,
       AVG(c.talk_seconds)                              AS avg_talk_seconds
FROM   ods.ods_call c
JOIN   dm.dim_disposition d ON d.disposition_code = c.disposition_code
GROUP  BY c.call_date, c.queue_id,
       CASE
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(bill|invoice|charge|refund)')    THEN 'BILLING'
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(password|login|locked|reset)')   THEN 'ACCESS'
         WHEN REGEXP_CONTAINS(d.disposition_desc, r'(?i)(cancel|churn|retention)')        THEN 'RETENTION'
         WHEN REGEXP_EXTRACT(d.disposition_desc, r'^\[([A-Z]{2,5})\]') IS NOT NULL
              THEN REGEXP_EXTRACT(d.disposition_desc, r'^\[([A-Z]{2,5})\]')
         ELSE 'OTHER'
       END,
       REGEXP_EXTRACT(d.disposition_desc, r'ref#(\d+)');
