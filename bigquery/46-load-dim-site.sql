-- 46-load-dim-site.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_org_unit
-- writes: dm.dim_site

-- Region/country/timezone are a hardcoded CASE — the site list changes once
-- a decade and nobody built a reference table. Migration: kept as-is.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_site AS
SELECT
  ou.org_unit_id                    AS site_sk,
  ou.site_code,
  ou.unit_name                      AS site_name,
  CASE ou.site_code WHEN 'MNL1' THEN 'APAC' WHEN 'BLR2' THEN 'APAC'
                    WHEN 'MTY3' THEN 'LATAM' ELSE 'UNK' END AS region,
  CASE ou.site_code WHEN 'MNL1' THEN 'PH' WHEN 'BLR2' THEN 'IN'
                    WHEN 'MTY3' THEN 'MX' ELSE 'UNK' END    AS country,
  CASE ou.site_code WHEN 'MNL1' THEN 'Asia/Manila' WHEN 'BLR2' THEN 'Asia/Kolkata'
                    WHEN 'MTY3' THEN 'America/Monterrey' ELSE 'UTC' END AS timezone
FROM ods.ods_org_unit ou
WHERE ou.unit_type = 'SITE' AND ou.snapshot_date = run_date;
