-- =============================================================================
-- check_comment_preservation.sql — AC #11: Comment preservation
--
-- Verifies that all 68 source Hive column COMMENTs are preserved as
-- semantically-equivalent BigQuery column descriptions.
--
-- The 68 Hive COMMENTs fall into 4 categories:
--   1. epoch SECONDS (legacy) — 42 columns across staging
--   2. epoch MILLISECONDS (legacy) — 22 columns across staging
--   3. Oracle string YYYYMMDDHH24MISS (legacy) — 4 columns
--   4. !! name says seconds, VALUES ARE MILLIS !! — 2 lie_ms columns
--
-- For each, we check that the BigQuery column has a non-empty description
-- containing the key semantic term.
--
-- Prints: preserved X/Y coverage line.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_comment_preservation.sql
-- =============================================================================

WITH expected_comments AS (
  -- epoch SECONDS columns (42)
  SELECT 'stg_crm_client' AS tbl, 'created_ts' AS col, 'SECONDS' AS keyword UNION ALL
  SELECT 'stg_crm_client', 'updated_ts', 'SECONDS' UNION ALL
  SELECT 'stg_crm_client_contact', 'created_ts', 'SECONDS' UNION ALL
  SELECT 'stg_crm_program', 'go_live_ts', 'SECONDS' UNION ALL
  SELECT 'stg_crm_program', 'updated_ts', 'SECONDS' UNION ALL
  SELECT 'stg_crm_sla_target', 'effective_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_agent', 'hire_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_agent', 'term_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_org_unit', 'created_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_employment_event', 'event_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_skill', 'created_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_agent_skill', 'effective_ts', 'SECONDS' UNION ALL
  SELECT 'stg_hr_agent_skill', 'expiry_ts', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_shift', 'created_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_schedule', 'start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_schedule', 'end_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_adherence_event', 'start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_adherence_event', 'end_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_forecast', 'interval_start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_wfm_timeoff_request', 'request_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_call', 'start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_call', 'answer_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_call', 'end_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_call_segment', 'start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_call_segment', 'end_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_queue', 'created_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_agent_state_event', 'start_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_agent_state_event', 'end_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_disposition_code', 'created_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_fin_rate_card', 'effective_ts', 'SECONDS' UNION ALL
  SELECT 'stg_fin_rate_card', 'expiry_ts', 'SECONDS' UNION ALL
  SELECT 'stg_tel_callback_request_delta', 'requested_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_tel_callback_request_delta', 'scheduled_epoch', 'SECONDS' UNION ALL
  SELECT 'stg_hr_attrition_event_delta', 'notice_epoch', 'SECONDS' UNION ALL

  -- epoch MILLISECONDS columns (22)
  SELECT 'stg_tkt_ticket', 'created_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tkt_ticket', 'updated_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tkt_ticket_event', 'event_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tkt_category', 'created_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_fin_invoice_line', 'created_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_fin_timesheet_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_fin_payroll_adj_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_crm_sla_credit_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tel_callback_request_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_wfm_shift_swap_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tkt_worklog_delta', 'log_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_tkt_worklog_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_hr_attrition_event_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_fin_rate_card_change_delta', 'change_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_interaction_export', 'start_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_interaction_export', 'end_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_survey_csat', 'survey_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_qa_forms', 'evaluated_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_ivr_logs', 'event_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_chat_transcripts', 'started_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_chat_transcripts', 'ended_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_roster', 'as_of_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_telco_invoice', 'billed_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_dialer_result', 'attempt_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_email_interaction', 'received_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_email_interaction', 'first_reply_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_email_interaction', 'resolved_ms', 'MILLISECONDS' UNION ALL
  SELECT 'stg_file_speech_analytics', 'analyzed_ms', 'MILLISECONDS' UNION ALL

  -- Oracle string YYYYMMDDHH24MISS columns (4)
  SELECT 'stg_crm_contract', 'start_dt', 'YYYYMMDDHH24MISS' UNION ALL
  SELECT 'stg_crm_contract', 'end_dt', 'YYYYMMDDHH24MISS' UNION ALL
  SELECT 'stg_crm_contract', 'signed_dt', 'YYYYMMDDHH24MISS' UNION ALL
  SELECT 'stg_crm_contract_line', 'effective_dt', 'YYYYMMDDHH24MISS' UNION ALL

  -- lie_ms columns (2)
  SELECT 'stg_fin_invoice', 'issued_ts_sec', 'MILLISECONDS' UNION ALL
  SELECT 'stg_fin_invoice', 'due_ts_sec', 'MILLISECONDS'
),

checks AS (
  SELECT e.tbl,
         e.col,
         e.keyword,
         COALESCE(c.description, '') AS bq_description,
         CASE WHEN c.description IS NULL OR c.description = '' THEN 'FAIL'
              WHEN UPPER(c.description) LIKE '%' || e.keyword || '%' THEN 'PASS'
              ELSE 'FAIL' END AS status
  FROM   expected_comments e
  LEFT   JOIN staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS c
         ON c.table_name = e.tbl AND c.column_name = e.col
         AND c.field_path = e.col
),

summary AS (
  SELECT COUNT(*) AS total,
         SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS preserved,
         SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS missing
  FROM   checks
)

-- Show failures first
SELECT 'MISSING_COMMENT' AS check_name,
       tbl || '.' || col AS detail,
       'expected keyword: ' || keyword || ', got: ' || SUBSTR(bq_description, 1, 60) AS extra,
       status
FROM   checks
WHERE  status = 'FAIL'

UNION ALL

-- Coverage line
SELECT 'COVERAGE',
       'preserved ' || CAST(s.preserved AS STRING) || '/'
       || CAST(s.total AS STRING) || ' Hive COMMENTs as BigQuery descriptions',
       CAST(s.missing AS STRING) || ' missing',
       CASE WHEN s.missing = 0 THEN 'PASS' ELSE 'FAIL' END
FROM   summary s

ORDER BY CASE WHEN status = 'FAIL' AND check_name = 'MISSING_COMMENT' THEN 0 ELSE 1 END,
         detail;
