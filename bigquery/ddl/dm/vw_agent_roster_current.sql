-- bigquery/ddl/dm/vw_agent_roster_current.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #7
-- Latest SCD-2 slice via ROW_NUMBER, ignoring the is_current flag analysts
-- never trusted.
--
-- Conversion notes:
--   - ROW_NUMBER() OVER (...) syntax is identical in BigQuery.
--   - Hive BOOLEAN comparison (asg.is_current = TRUE) works in BigQuery as-is.
--   - Subquery aliasing and LEFT JOIN syntax identical.

CREATE VIEW IF NOT EXISTS dm.vw_agent_roster_current AS
SELECT latest.agent_id, latest.employee_no, latest.org_unit_id, latest.job_grade,
       latest.employment_type, latest.status, latest.eff_from_ts,
       asg.program_id AS current_program_id,
       asg.queue_id   AS current_queue_id,
       asg.role_on_program
FROM (
  SELECT h.*,
         ROW_NUMBER() OVER (PARTITION BY h.agent_id ORDER BY h.eff_from_ts DESC) AS rn
  FROM   ods.ods_agent_scd2 h
) latest
LEFT   JOIN ods.ods_agent_assignment_scd2 asg
       ON asg.agent_id = latest.agent_id AND asg.is_current = TRUE
WHERE  latest.rn = 1;
