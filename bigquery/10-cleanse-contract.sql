-- 10-cleanse-contract.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_crm_contract
-- writes: ods.ods_contract

-- Cleanse staging.stg_crm_contract -> ods.ods_contract: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: STRING 'YYYYMMDDHHMMSS' → PARSE_TIMESTAMP per EPOCH-POLICY.md.
-- NULL propagation: PARSE_TIMESTAMP returns NULL for NULL input (e.g. end_dt).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_contract WHERE snapshot_date = run_date;

INSERT INTO ods.ods_contract
SELECT
  s.contract_id                                                          AS contract_id,
  s.client_id                                                            AS client_id,
  s.program_id                                                           AS program_id,
  s.contract_no                                                          AS contract_no,
  PARSE_TIMESTAMP('%Y%m%d%H%M%S', s.start_dt)                           AS start_ts,
  PARSE_TIMESTAMP('%Y%m%d%H%M%S', s.end_dt)                             AS end_ts,
  UPPER(TRIM(s.billing_model))                                           AS billing_model,
  UPPER(TRIM(s.currency))                                                AS currency,
  PARSE_TIMESTAMP('%Y%m%d%H%M%S', s.signed_dt)                          AS signed_ts,
  UPPER(TRIM(s.status))                                                  AS status,
  run_date                                                               AS snapshot_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.contract_id ORDER BY s.start_dt DESC) AS rn
  FROM staging.stg_crm_contract s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
