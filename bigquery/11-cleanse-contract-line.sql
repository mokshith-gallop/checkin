-- 11-cleanse-contract-line.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_crm_contract_line
-- writes: ods.ods_contract_line

-- Cleanse staging.stg_crm_contract_line -> ods.ods_contract_line: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: STRING 'YYYYMMDDHHMMSS' → PARSE_TIMESTAMP per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_contract_line WHERE snapshot_date = run_date;

INSERT INTO ods.ods_contract_line
SELECT
  s.contract_line_id                                                     AS contract_line_id,
  s.contract_id                                                          AS contract_id,
  s.line_no                                                              AS line_no,
  UPPER(TRIM(s.service_code))                                            AS service_code,
  UPPER(TRIM(s.uom))                                                     AS uom,
  s.unit_rate                                                            AS unit_rate,
  s.min_commit                                                           AS min_commit,
  PARSE_TIMESTAMP('%Y%m%d%H%M%S', s.effective_dt)                        AS effective_ts,
  run_date                                                               AS snapshot_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.contract_line_id ORDER BY s.effective_dt DESC) AS rn
  FROM staging.stg_crm_contract_line s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
