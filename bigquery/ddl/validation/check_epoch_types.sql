-- =============================================================================
-- check_epoch_types.sql — AC #2: Epoch encoding validation
--
-- Verifies:
--   1. All epoch-tagged columns in STAGING are INT64 (not TIMESTAMP).
--   2. All epoch-derived columns in ODS/DM are TIMESTAMP (not INT64/STRING).
--   3. The 2 lie_ms columns (issued_ts_sec, due_ts_sec) have column
--      descriptions containing 'MILLISECONDS'.
--   4. Oracle string columns (start_dt, end_dt, signed_dt, effective_dt) in
--      staging are STRING with description containing 'YYYYMMDDHH24MISS'.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_epoch_types.sql
-- =============================================================================

-- Check 1: Staging epoch columns must be INT64
WITH stg_epoch_cols AS (
  SELECT table_name, column_name, data_type,
         CASE WHEN data_type = 'INT64' THEN 'PASS' ELSE 'FAIL' END AS status
  FROM   staging.INFORMATION_SCHEMA.COLUMNS
  WHERE  column_name IN (
    -- epoch_sec columns
    'created_ts', 'updated_ts', 'go_live_ts', 'effective_ts',
    'hire_ts', 'term_ts', 'event_ts', 'expiry_ts',
    'created_epoch', 'start_epoch', 'end_epoch', 'answer_epoch',
    'request_epoch', 'interval_start_epoch',
    'requested_epoch', 'scheduled_epoch', 'notice_epoch',
    -- epoch_ms columns
    'created_ms', 'updated_ms', 'event_ms', 'change_ms',
    'start_ms', 'end_ms', 'survey_ms', 'evaluated_ms',
    'started_ms', 'ended_ms', 'as_of_ms', 'billed_ms',
    'attempt_ms', 'received_ms', 'first_reply_ms', 'resolved_ms',
    'analyzed_ms', 'log_ms',
    -- lie_ms columns
    'issued_ts_sec', 'due_ts_sec'
  )
),

-- Check 2: ODS/DM timestamp columns must be TIMESTAMP (not INT64)
ods_ts_cols AS (
  SELECT table_name, column_name, data_type,
         CASE WHEN data_type = 'TIMESTAMP' THEN 'PASS' ELSE 'FAIL' END AS status
  FROM   ods.INFORMATION_SCHEMA.COLUMNS
  WHERE  (column_name LIKE '%_ts' OR column_name LIKE '%_ts_%')
    AND  data_type IN ('TIMESTAMP', 'INT64', 'STRING')
),

-- Check 3: Lie columns must have MILLISECONDS in description
lie_cols AS (
  SELECT table_name, column_name, data_type,
         COALESCE(c.description, '') AS col_description,
         CASE WHEN UPPER(COALESCE(c.description, '')) LIKE '%MILLISECONDS%' THEN 'PASS'
              ELSE 'FAIL' END AS status
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS c
  WHERE  column_name IN ('issued_ts_sec', 'due_ts_sec')
    AND  table_name = 'stg_fin_invoice'
),

-- Check 4: Oracle string columns must be STRING with correct description
ora_str_cols AS (
  SELECT table_name, column_name, data_type,
         COALESCE(c.description, '') AS col_description,
         CASE WHEN data_type = 'STRING'
               AND UPPER(COALESCE(c.description, '')) LIKE '%YYYYMMDDHH24MISS%'
              THEN 'PASS' ELSE 'FAIL' END AS status
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS c
  WHERE  column_name IN ('start_dt', 'end_dt', 'signed_dt', 'effective_dt')
    AND  table_name IN ('stg_crm_contract', 'stg_crm_contract_line')
)

-- Combined results
SELECT 'stg_epoch_int64' AS check_name, table_name, column_name, data_type, status
FROM   stg_epoch_cols
WHERE  status = 'FAIL'
UNION ALL
SELECT 'ods_epoch_timestamp', table_name, column_name, data_type, status
FROM   ods_ts_cols
WHERE  status = 'FAIL'
UNION ALL
SELECT 'lie_ms_description', table_name, column_name, data_type, status
FROM   lie_cols
WHERE  status = 'FAIL'
UNION ALL
SELECT 'ora_str_description', table_name, column_name, data_type, status
FROM   ora_str_cols
WHERE  status = 'FAIL'
UNION ALL
-- Summary row: PASS if no failures above
SELECT 'OVERALL',
       CAST(COUNT(*) AS STRING) || ' checks',
       CASE WHEN SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) = 0 THEN 'ALL PASS'
            ELSE CAST(SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS STRING) || ' FAILURES'
       END,
       '',
       CASE WHEN SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
  SELECT status FROM stg_epoch_cols
  UNION ALL SELECT status FROM ods_ts_cols
  UNION ALL SELECT status FROM lie_cols
  UNION ALL SELECT status FROM ora_str_cols
);
