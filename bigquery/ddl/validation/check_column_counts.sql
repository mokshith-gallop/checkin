-- =============================================================================
-- check_column_counts.sql — AC #1: Column count parity
--
-- Verifies that every table in INFORMATION_SCHEMA.COLUMNS has exactly the
-- expected number of columns (source data columns + inlined partition columns).
--
-- Usage:
--   bq query --nouse_legacy_sql < check_column_counts.sql
--
-- Expected result: 100 rows, all with status = 'PASS'.
-- =============================================================================

WITH expected AS (
  -- Staging: sqoop mirrors (27)
  SELECT 'staging' AS ds, 'stg_crm_client' AS tbl, 9 AS expected_cols UNION ALL
  SELECT 'staging', 'stg_crm_client_contact', 9 UNION ALL
  SELECT 'staging', 'stg_crm_contract', 11 UNION ALL
  SELECT 'staging', 'stg_crm_contract_line', 9 UNION ALL
  SELECT 'staging', 'stg_crm_program', 11 UNION ALL
  SELECT 'staging', 'stg_crm_sla_target', 8 UNION ALL
  SELECT 'staging', 'stg_hr_agent', 12 UNION ALL
  SELECT 'staging', 'stg_hr_org_unit', 9 UNION ALL
  SELECT 'staging', 'stg_hr_employment_event', 8 UNION ALL
  SELECT 'staging', 'stg_hr_skill', 6 UNION ALL
  SELECT 'staging', 'stg_hr_agent_skill', 8 UNION ALL
  SELECT 'staging', 'stg_wfm_shift', 9 UNION ALL
  SELECT 'staging', 'stg_wfm_schedule', 10 UNION ALL
  SELECT 'staging', 'stg_wfm_adherence_event', 8 UNION ALL
  SELECT 'staging', 'stg_wfm_forecast', 7 UNION ALL
  SELECT 'staging', 'stg_wfm_timeoff_request', 8 UNION ALL
  SELECT 'staging', 'stg_tel_call', 13 UNION ALL
  SELECT 'staging', 'stg_tel_call_segment', 8 UNION ALL
  SELECT 'staging', 'stg_tel_queue', 8 UNION ALL
  SELECT 'staging', 'stg_tel_agent_state_event', 7 UNION ALL
  SELECT 'staging', 'stg_tel_disposition_code', 6 UNION ALL
  SELECT 'staging', 'stg_tkt_ticket', 12 UNION ALL
  SELECT 'staging', 'stg_tkt_ticket_event', 8 UNION ALL
  SELECT 'staging', 'stg_tkt_category', 6 UNION ALL
  SELECT 'staging', 'stg_fin_invoice', 11 UNION ALL
  SELECT 'staging', 'stg_fin_invoice_line', 9 UNION ALL
  SELECT 'staging', 'stg_fin_rate_card', 8 UNION ALL
  -- Staging: delta feeds (8)
  SELECT 'staging', 'stg_fin_timesheet_delta', 10 UNION ALL
  SELECT 'staging', 'stg_fin_payroll_adj_delta', 8 UNION ALL
  SELECT 'staging', 'stg_crm_sla_credit_delta', 9 UNION ALL
  SELECT 'staging', 'stg_tel_callback_request_delta', 9 UNION ALL
  SELECT 'staging', 'stg_wfm_shift_swap_delta', 9 UNION ALL
  SELECT 'staging', 'stg_tkt_worklog_delta', 9 UNION ALL
  SELECT 'staging', 'stg_hr_attrition_event_delta', 10 UNION ALL
  SELECT 'staging', 'stg_fin_rate_card_change_delta', 8 UNION ALL
  -- Staging: file feeds (10)
  SELECT 'staging', 'stg_file_interaction_export', 10 UNION ALL
  SELECT 'staging', 'stg_file_survey_csat', 9 UNION ALL
  SELECT 'staging', 'stg_file_qa_forms', 10 UNION ALL
  SELECT 'staging', 'stg_file_ivr_logs', 7 UNION ALL
  SELECT 'staging', 'stg_file_chat_transcripts', 9 UNION ALL
  SELECT 'staging', 'stg_file_roster', 8 UNION ALL
  SELECT 'staging', 'stg_file_telco_invoice', 9 UNION ALL
  SELECT 'staging', 'stg_file_dialer_result', 9 UNION ALL
  SELECT 'staging', 'stg_file_email_interaction', 9 UNION ALL
  SELECT 'staging', 'stg_file_speech_analytics', 9 UNION ALL
  -- ODS: cleanse (15)
  SELECT 'ods', 'ods_program', 11 UNION ALL
  SELECT 'ods', 'ods_contract', 11 UNION ALL
  SELECT 'ods', 'ods_contract_line', 9 UNION ALL
  SELECT 'ods', 'ods_org_unit', 9 UNION ALL
  SELECT 'ods', 'ods_queue', 8 UNION ALL
  SELECT 'ods', 'ods_schedule', 10 UNION ALL
  SELECT 'ods', 'ods_adherence_event', 9 UNION ALL
  SELECT 'ods', 'ods_call', 16 UNION ALL
  SELECT 'ods', 'ods_ivr_session', 9 UNION ALL
  SELECT 'ods', 'ods_chat_session', 11 UNION ALL
  SELECT 'ods', 'ods_email_interaction', 10 UNION ALL
  SELECT 'ods', 'ods_survey_response', 9 UNION ALL
  SELECT 'ods', 'ods_qa_evaluation', 12 UNION ALL
  SELECT 'ods', 'ods_interaction', 13 UNION ALL
  SELECT 'ods', 'ods_dialer_attempt', 9 UNION ALL
  -- ODS: delta-merge (8)
  SELECT 'ods', 'ods_timesheet', 9 UNION ALL
  SELECT 'ods', 'ods_payroll_adjustment', 6 UNION ALL
  SELECT 'ods', 'ods_sla_credit', 7 UNION ALL
  SELECT 'ods', 'ods_callback_request', 8 UNION ALL
  SELECT 'ods', 'ods_shift_swap', 8 UNION ALL
  SELECT 'ods', 'ods_ticket_worklog', 8 UNION ALL
  SELECT 'ods', 'ods_attrition_event', 9 UNION ALL
  SELECT 'ods', 'ods_rate_card', 9 UNION ALL
  -- ODS: SCD-2 (3)
  SELECT 'ods', 'ods_agent_scd2', 11 UNION ALL
  SELECT 'ods', 'ods_agent_skill_scd2', 10 UNION ALL
  SELECT 'ods', 'ods_agent_assignment_scd2', 9 UNION ALL
  -- ODS: ACID (4)
  SELECT 'ods', 'ods_client_acid', 8 UNION ALL
  SELECT 'ods', 'ods_agent_acid', 10 UNION ALL
  SELECT 'ods', 'ods_ticket_acid', 10 UNION ALL
  SELECT 'ods', 'ods_invoice_acid', 10 UNION ALL
  -- DM: dimensions (9)
  SELECT 'dm', 'dim_date', 12 UNION ALL
  SELECT 'dm', 'dim_agent', 12 UNION ALL
  SELECT 'dm', 'dim_client', 9 UNION ALL
  SELECT 'dm', 'dim_program', 11 UNION ALL
  SELECT 'dm', 'dim_queue', 7 UNION ALL
  SELECT 'dm', 'dim_site', 6 UNION ALL
  SELECT 'dm', 'dim_shift', 8 UNION ALL
  SELECT 'dm', 'dim_org', 11 UNION ALL
  SELECT 'dm', 'dim_disposition', 5 UNION ALL
  -- DM: facts (9)
  SELECT 'dm', 'fact_interaction', 13 UNION ALL
  SELECT 'dm', 'fact_agent_activity', 7 UNION ALL
  SELECT 'dm', 'fact_queue_interval', 10 UNION ALL
  SELECT 'dm', 'fact_csat_survey', 10 UNION ALL
  SELECT 'dm', 'fact_qa_evaluation', 10 UNION ALL
  SELECT 'dm', 'fact_billing_line', 11 UNION ALL
  SELECT 'dm', 'fact_adherence_daily', 8 UNION ALL
  SELECT 'dm', 'fact_ticket', 12 UNION ALL
  SELECT 'dm', 'fact_ivr_path', 8 UNION ALL
  -- DM: aggregates (7)
  SELECT 'dm', 'agg_agent_daily', 10 UNION ALL
  SELECT 'dm', 'agg_agent_weekly', 8 UNION ALL
  SELECT 'dm', 'agg_program_monthly', 9 UNION ALL
  SELECT 'dm', 'agg_queue_hourly', 9 UNION ALL
  SELECT 'dm', 'agg_csat_rollup_monthly', 9 UNION ALL
  SELECT 'dm', 'agg_billing_monthly', 7 UNION ALL
  SELECT 'dm', 'agg_site_daily', 7
),
actual AS (
  SELECT table_schema AS ds, table_name AS tbl, COUNT(*) AS actual_cols
  FROM   staging.INFORMATION_SCHEMA.COLUMNS GROUP BY 1, 2
  UNION ALL
  SELECT table_schema, table_name, COUNT(*)
  FROM   ods.INFORMATION_SCHEMA.COLUMNS GROUP BY 1, 2
  UNION ALL
  SELECT table_schema, table_name, COUNT(*)
  FROM   dm.INFORMATION_SCHEMA.COLUMNS GROUP BY 1, 2
)
SELECT e.ds,
       e.tbl,
       e.expected_cols,
       COALESCE(a.actual_cols, 0) AS actual_cols,
       CASE
         WHEN a.actual_cols IS NULL THEN 'MISSING'
         WHEN a.actual_cols = e.expected_cols THEN 'PASS'
         ELSE 'FAIL'
       END AS status
FROM   expected e
LEFT   JOIN actual a ON a.ds = e.ds AND a.tbl = e.tbl
ORDER  BY CASE WHEN a.actual_cols IS NULL OR a.actual_cols <> e.expected_cols THEN 0 ELSE 1 END,
          e.ds, e.tbl;
