-- 42-load-dim-agent.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_agent_scd2, ods.ods_agent_acid, ods.ods_org_unit
-- writes: dm.dim_agent

-- Current-slice agent dim. agent_sk reuses agent_id (legacy decision —
-- surrogate pipeline was never built). Team/site attributes from org tree.
-- from_unixtime(unix_timestamp(hire_ts), 'yyyyMMdd') → FORMAT_TIMESTAMP('%Y%m%d', hire_ts).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_agent AS
SELECT
  a.agent_id                                            AS agent_sk,
  a.agent_id,
  a.employee_no,
  ac.full_name,
  a.job_grade,
  a.employment_type,
  a.org_unit_id,
  ou.unit_name                                          AS team_name,
  COALESCE(ou.site_code, 'UNK')                         AS site_code,
  a.status,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', ac.hire_ts) AS INT64)  AS hire_date_key,
  a.is_current
FROM ods.ods_agent_scd2 a
JOIN ods.ods_agent_acid ac ON ac.agent_id = a.agent_id
LEFT JOIN ods.ods_org_unit ou
       ON ou.org_unit_id = a.org_unit_id
      AND ou.snapshot_date = run_date
WHERE a.is_current = TRUE;
