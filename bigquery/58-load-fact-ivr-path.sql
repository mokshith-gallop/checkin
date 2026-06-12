-- 58-load-fact-ivr-path.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_ivr_session
-- writes: dm.fact_ivr_path

-- unix_timestamp(ts) → UNIX_SECONDS(CAST(ts AS TIMESTAMP)).
-- from_unixtime(unix_timestamp(ts), 'yyyyMMdd') → CAST(FORMAT_TIMESTAMP('%Y%m%d', ts) AS INT64).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_ivr_path WHERE date_key = date_key_val;

INSERT INTO dm.fact_ivr_path
SELECT
  s.session_ref,
  s.client_code,
  s.menu_path_full,
  s.hops,
  s.contained_flag,
  s.exit_key,
  CAST(UNIX_SECONDS(CAST(s.last_event_ts AS TIMESTAMP)) - UNIX_SECONDS(CAST(s.first_event_ts AS TIMESTAMP)) AS INT64)
                                                                    AS duration_seconds,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', s.first_event_ts) AS INT64)      AS date_key
FROM ods.ods_ivr_session s
WHERE s.event_date = run_date;
