-- 09-cleanse-program.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_crm_program
-- writes: ods.ods_program

-- Cleanse staging.stg_crm_program -> ods.ods_program: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: seconds (CRM source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_program WHERE snapshot_date = run_date;

INSERT INTO ods.ods_program
SELECT
  s.program_id                                                           AS program_id,
  s.client_id                                                            AS client_id,
  s.program_code                                                         AS program_code,
  s.program_name                                                         AS program_name,
  UPPER(TRIM(s.line_of_business))                                        AS line_of_business,
  UPPER(TRIM(s.channel_mix))                                             AS channel_mix,
  UPPER(TRIM(s.site_code))                                               AS site_code,
  UPPER(TRIM(s.status))                                                  AS status,
  TIMESTAMP_SECONDS(s.go_live_ts)                                        AS go_live_ts,
  TIMESTAMP_SECONDS(s.updated_ts)                                        AS updated_ts,
  run_date                                                               AS snapshot_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.program_id ORDER BY s.go_live_ts DESC) AS rn
  FROM staging.stg_crm_program s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
