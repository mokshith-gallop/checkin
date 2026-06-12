-- 51-load-fact-agent-activity.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_tel_agent_state_event, ods.ods_adherence_event, dm.dim_agent
-- writes: dm.fact_agent_activity

-- LAYER-SKIP TRAP: state events come straight from staging (raw epoch math —
-- volume made the team skip the ods hop). Approved adherence exceptions are
-- subtracted from AUX time.
-- from_unixtime(epoch) → TIMESTAMP_SECONDS(epoch).
-- unix_timestamp(ts) → UNIX_SECONDS(CAST(ts AS TIMESTAMP)).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_agent_activity WHERE date_key = date_key_val;

INSERT INTO dm.fact_agent_activity
SELECT
  COALESCE(a.agent_sk, -1)                                        AS agent_sk,
  e.state_code,
  SUM(e.end_epoch - e.start_epoch)
    - COALESCE(MAX(adj.approved_secs), 0)                         AS state_seconds,
  CAST(COUNT(*) AS INT64)                                         AS occurrence_count,
  TIMESTAMP_SECONDS(MIN(e.start_epoch))                           AS first_state_ts,
  TIMESTAMP_SECONDS(MAX(e.end_epoch))                             AS last_state_ts,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_SECONDS(MIN(e.start_epoch))) AS INT64) AS date_key
FROM staging.stg_tel_agent_state_event e
LEFT JOIN dm.dim_agent a ON a.agent_id = e.agent_id AND a.is_current = TRUE
LEFT JOIN (
  SELECT x.agent_id,
         SUM(UNIX_SECONDS(CAST(x.end_ts AS TIMESTAMP)) - UNIX_SECONDS(CAST(x.start_ts AS TIMESTAMP))) AS approved_secs
  FROM ods.ods_adherence_event x
  WHERE x.event_date = run_date AND x.approved_flag = TRUE
  GROUP BY x.agent_id
) adj ON adj.agent_id = e.agent_id AND e.state_code LIKE 'AUX%'
WHERE e.load_date = run_date
GROUP BY COALESCE(a.agent_sk, -1), e.state_code;
