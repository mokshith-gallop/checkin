-- bigquery/ddl/dm/vw_shrinkage_analysis.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #13
-- Scheduled vs productive time with schedule/shift joins.
--
-- Conversion notes:
--   - The Hive date conversion chain:
--       CAST(from_unixtime(unix_timestamp(CAST(f.date_key AS STRING), 'yyyyMMdd'),
--            'yyyy-MM-dd') AS STRING)
--     converts an INT date_key (e.g., 20240115) to a string 'YYYY-MM-DD'.
--     In BigQuery this is done with PARSE_DATE + FORMAT_DATE:
--       FORMAT_DATE('%Y-%m-%d', PARSE_DATE('%Y%m%d', CAST(f.date_key AS STRING)))
--     Since ods.ods_schedule.sched_date is now DATE in BigQuery (not STRING),
--     we compare DATE to DATE directly:
--       s.sched_date = PARSE_DATE('%Y%m%d', CAST(f.date_key AS STRING))
--   - Hive COUNT(DISTINCT ...) → BigQuery COUNT(DISTINCT ...) (identical).
--   - Hive NULLIF() → BigQuery NULLIF() (identical).

CREATE VIEW IF NOT EXISTS dm.vw_shrinkage_analysis AS
SELECT f.date_key,
       a.site_code,
       SUM(f.scheduled_minutes)                          AS scheduled_minutes,
       SUM(f.worked_minutes)                             AS worked_minutes,
       SUM(f.exception_minutes + f.timeoff_minutes)      AS shrinkage_minutes,
       SUM(f.exception_minutes + f.timeoff_minutes)
         / NULLIF(SUM(f.scheduled_minutes), 0) * 100     AS shrinkage_pct,
       COUNT(DISTINCT s.schedule_id)                     AS schedules,
       COUNT(DISTINCT sh.shift_sk)                       AS overnight_shifts
FROM   dm.fact_adherence_daily f
JOIN   dm.dim_agent a ON a.agent_sk = f.agent_sk
LEFT   JOIN ods.ods_schedule s
       ON s.agent_id = a.agent_id
      AND s.sched_date = PARSE_DATE('%Y%m%d', CAST(f.date_key AS STRING))
LEFT   JOIN dm.dim_shift sh ON sh.shift_id = s.shift_id AND sh.overnight_flag = TRUE
GROUP  BY f.date_key, a.site_code;
