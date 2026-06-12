-- 44-load-dim-program.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_program, ods.ods_contract
-- writes: dm.dim_program

-- from_unixtime(unix_timestamp(go_live_ts), 'yyyyMMdd') → FORMAT_TIMESTAMP('%Y%m%d', go_live_ts).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_program AS
SELECT
  p.program_id                      AS program_sk,
  p.program_id,
  p.program_code,
  p.program_name,
  p.client_id,
  p.line_of_business,
  p.channel_mix,
  p.site_code,
  COALESCE(k.billing_model, 'PER_FTE') AS billing_model,
  p.status,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', p.go_live_ts) AS INT64) AS go_live_date_key
FROM ods.ods_program p
LEFT JOIN (
  SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.program_id ORDER BY c.signed_ts DESC) AS rn
  FROM ods.ods_contract c
  WHERE c.snapshot_date = run_date AND c.status = 'EXECUTED'
) k ON k.program_id = p.program_id AND k.rn = 1
WHERE p.snapshot_date = run_date;
