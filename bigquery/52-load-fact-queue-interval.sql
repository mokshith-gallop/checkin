-- 52-load-fact-queue-interval.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_call, dm.dim_queue, staging.stg_crm_sla_target
-- writes: dm.fact_queue_interval

-- 30-minute interval queue stats. SL threshold pulled from STAGING sla
-- targets (layer-skip trap); SL_20_80 means 80% answered within 20s.
-- floor(unix_timestamp(ts)/1800)*1800 → TIMESTAMP_SECONDS(CAST(FLOOR(UNIX_SECONDS(CAST(ts AS TIMESTAMP))/1800)*1800 AS INT64)).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_queue_interval WHERE date_key = date_key_val;

INSERT INTO dm.fact_queue_interval
SELECT
  COALESCE(q.queue_sk, -1)                                  AS queue_sk,
  TIMESTAMP_SECONDS(CAST(FLOOR(UNIX_SECONDS(CAST(c.start_ts AS TIMESTAMP)) / 1800) * 1800 AS INT64))
                                                             AS interval_start_ts,
  CAST(COUNT(*) AS INT64)                                   AS offered,
  CAST(SUM(CASE WHEN NOT c.abandoned_flag THEN 1 ELSE 0 END) AS INT64) AS answered,
  CAST(SUM(CASE WHEN c.abandoned_flag THEN 1 ELSE 0 END) AS INT64)     AS abandoned,
  CAST(SUM(CASE WHEN NOT c.abandoned_flag AND c.ring_seconds <= COALESCE(MAX(t.sl_threshold), 20)
                THEN 1 ELSE 0 END) AS INT64)                AS answered_in_sl,
  CAST(COALESCE(MAX(t.sl_threshold), 20) AS INT64)         AS sl_threshold_sec,
  CAST(AVG(CASE WHEN NOT c.abandoned_flag THEN c.ring_seconds END) AS NUMERIC) AS avg_speed_answer_sec,
  CAST(AVG(c.talk_seconds + c.hold_seconds + c.acw_seconds) AS NUMERIC) AS avg_handle_sec,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', c.start_ts) AS INT64)     AS date_key
FROM ods.ods_call c
LEFT JOIN dm.dim_queue q ON q.queue_id = c.queue_id
LEFT JOIN (
  SELECT s.queue_id, CAST(20 AS INT64) AS sl_threshold   -- parsed out of SL_20_80 by convention
  FROM staging.stg_crm_sla_target s
  WHERE s.metric_code = 'SL_20_80'
) t ON t.queue_id = c.queue_id
WHERE c.call_date = run_date
GROUP BY COALESCE(q.queue_sk, -1),
         TIMESTAMP_SECONDS(CAST(FLOOR(UNIX_SECONDS(CAST(c.start_ts AS TIMESTAMP)) / 1800) * 1800 AS INT64)),
         CAST(FORMAT_TIMESTAMP('%Y%m%d', c.start_ts) AS INT64);
