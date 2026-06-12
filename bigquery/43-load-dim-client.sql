-- 43-load-dim-client.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_client_acid, staging.stg_crm_client_contact
-- writes: dm.dim_client

-- LAYER-SKIP TRAP: primary contact comes straight from STAGING (the cleanse
-- for client contacts was never built). Target architecture must either
-- replicate the skip or remediate it — flag, don't silently fix.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_client AS
SELECT
  c.client_id                       AS client_sk,
  c.client_id,
  c.client_code,
  c.client_name,
  c.industry,
  c.hq_country,
  ct.full_name                      AS primary_contact_name,
  ct.email                          AS primary_contact_email,
  c.status
FROM ods.ods_client_acid c
LEFT JOIN (
  SELECT k.*, ROW_NUMBER() OVER (PARTITION BY k.client_id
                                 ORDER BY k.is_primary DESC, k.created_ts DESC) AS rn
  FROM staging.stg_crm_client_contact k
  WHERE k.load_date = run_date
) ct ON ct.client_id = c.client_id AND ct.rn = 1;
