-- 56-load-fact-adherence-daily.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_schedule, ods.ods_adherence_event, staging.stg_wfm_timeoff_request, dm.dim_agent
-- writes: dm.fact_adherence_daily

-- Schedule vs exceptions vs PTO per agent-day. Timeoff comes straight from
-- staging (layer-skip trap).
-- unix_timestamp(sched_date, 'yyyy-MM-dd') → CAST(FORMAT_DATE('%Y%m%d', CAST(sched_date AS DATE)) AS INT64).
-- CAST(... AS DECIMAL(5,2)) → CAST(... AS NUMERIC).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_adherence_daily WHERE date_key = date_key_val;

INSERT INTO dm.fact_adherence_daily
SELECT
  COALESCE(a.agent_sk, -1)                                        AS agent_sk,
  CAST(SUM(s.paid_minutes) AS INT64)                              AS scheduled_minutes,
  CAST(SUM(s.paid_minutes) - COALESCE(MAX(x.exc_minutes), 0) AS INT64) AS worked_minutes,
  CAST(COALESCE(MAX(x.exc_minutes), 0) AS INT64)                 AS exception_minutes,
  CAST(COALESCE(MAX(pto.pto_minutes), 0) AS INT64)               AS timeoff_minutes,
  CAST(100.0 * (SUM(s.paid_minutes) - COALESCE(MAX(x.exc_minutes), 0))
       / NULLIF(SUM(s.paid_minutes), 0) AS NUMERIC)              AS adherence_pct,
  CAST(0 AS NUMERIC)                                              AS occupancy_pct,  -- backfilled by agg job
  CAST(FORMAT_DATE('%Y%m%d', CAST(s.sched_date AS DATE)) AS INT64) AS date_key
FROM ods.ods_schedule s
LEFT JOIN dm.dim_agent a ON a.agent_id = s.agent_id AND a.is_current = TRUE
LEFT JOIN (
  SELECT e.agent_id, SUM(e.exception_minutes) AS exc_minutes
  FROM ods.ods_adherence_event e
  WHERE e.event_date = run_date
  GROUP BY e.agent_id
) x ON x.agent_id = s.agent_id
LEFT JOIN (
  SELECT t.agent_id, COUNT(*) * 480 AS pto_minutes
  FROM staging.stg_wfm_timeoff_request t
  WHERE t.status = 'APPROVED'
    AND t.start_date <= run_date AND t.end_date >= run_date
  GROUP BY t.agent_id
) pto ON pto.agent_id = s.agent_id
WHERE s.sched_date = run_date
GROUP BY COALESCE(a.agent_sk, -1), s.sched_date;
