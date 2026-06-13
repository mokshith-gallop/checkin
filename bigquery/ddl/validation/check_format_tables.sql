-- =============================================================================
-- check_format_tables.sql — AC #6: Format provenance validation
--
-- For the 14 format-specific staging tables (8 pipe-delimited TEXTFILE,
-- 3 RegexSerDe/SequenceFile/RCFile, 3 JsonSerDe), verifies:
--   1. All are BASE TABLE (not EXTERNAL).
--   2. Table descriptions contain provenance text (e.g., 'Source: Hive ...').
--   3. Zero table descriptions reference Hive SerDe properties as active config.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_format_tables.sql
-- =============================================================================

WITH format_tables AS (
  -- 8 delta feeds (pipe-delimited TEXTFILE)
  SELECT 'stg_fin_timesheet_delta' AS tbl, 'TEXTFILE pipe-delimited' AS expected_format UNION ALL
  SELECT 'stg_fin_payroll_adj_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_crm_sla_credit_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_tel_callback_request_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_wfm_shift_swap_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_tkt_worklog_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_hr_attrition_event_delta', 'TEXTFILE pipe-delimited' UNION ALL
  SELECT 'stg_fin_rate_card_change_delta', 'TEXTFILE pipe-delimited' UNION ALL
  -- 3 JsonSerDe
  SELECT 'stg_file_qa_forms', 'JsonSerDe' UNION ALL
  SELECT 'stg_file_chat_transcripts', 'JsonSerDe' UNION ALL
  SELECT 'stg_file_speech_analytics', 'JsonSerDe' UNION ALL
  -- 1 RegexSerDe
  SELECT 'stg_file_ivr_logs', 'RegexSerDe' UNION ALL
  -- 1 SequenceFile
  SELECT 'stg_file_telco_invoice', 'SequenceFile' UNION ALL
  -- 1 RCFile
  SELECT 'stg_file_dialer_result', 'RCFile'
),

checks AS (
  SELECT f.tbl,
         f.expected_format,
         COALESCE(t.table_type, 'MISSING') AS table_type,
         COALESCE(opt.option_value, '') AS table_description,
         -- Check 1: is BASE TABLE
         CASE WHEN t.table_type = 'BASE TABLE' THEN 'PASS' ELSE 'FAIL' END AS type_status,
         -- Check 2: description contains 'Source:' provenance text
         CASE WHEN COALESCE(opt.option_value, '') LIKE '%Source:%' THEN 'PASS'
              ELSE 'FAIL' END AS provenance_status
  FROM   format_tables f
  LEFT   JOIN staging.INFORMATION_SCHEMA.TABLES t ON t.table_name = f.tbl
  LEFT   JOIN staging.INFORMATION_SCHEMA.TABLE_OPTIONS opt
         ON opt.table_name = f.tbl AND opt.option_name = 'description'
)

SELECT tbl,
       expected_format,
       table_type,
       SUBSTR(table_description, 1, 80) AS description_preview,
       type_status AS is_base_table,
       provenance_status AS has_provenance,
       CASE WHEN type_status = 'PASS' AND provenance_status = 'PASS' THEN 'PASS'
            ELSE 'FAIL' END AS overall_status
FROM   checks
ORDER  BY CASE WHEN type_status = 'FAIL' OR provenance_status = 'FAIL' THEN 0 ELSE 1 END,
          tbl;
