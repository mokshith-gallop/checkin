-- 49-load-dim-disposition.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_tel_disposition_code
-- writes: dm.dim_disposition

-- LAYER-SKIP TRAP: reads staging directly (no ods cleanse for dispositions).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_disposition AS
SELECT
  DENSE_RANK() OVER (ORDER BY d.disposition_code) AS disposition_sk,
  d.disposition_code,
  d.disposition_desc,
  d.category,
  d.billable_flag
FROM (
  SELECT d.*, ROW_NUMBER() OVER (PARTITION BY d.disposition_code
                                 ORDER BY d.created_epoch DESC) AS rn
  FROM staging.stg_tel_disposition_code d
  WHERE d.load_date = run_date
) d
WHERE d.rn = 1;
