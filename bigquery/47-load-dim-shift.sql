-- 47-load-dim-shift.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_wfm_shift
-- writes: dm.dim_shift

-- LAYER-SKIP TRAP: reads staging directly (no ods cleanse exists for shifts).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_shift AS
SELECT s.shift_id AS shift_sk, s.shift_id, s.shift_code, s.shift_name, s.start_hhmm,
       s.end_hhmm, s.overnight_flag, s.site_code
FROM (
  SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.shift_id ORDER BY s.created_epoch DESC) AS rn
  FROM staging.stg_wfm_shift s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
