-- 17-cleanse-ivr-session.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_ivr_logs
-- writes: ods.ods_ivr_session

-- IVR traversal events (RegexSerDe-parsed pipe format, epoch MILLIS) rolled
-- up to one row per session. STRING_AGG preserves menu order only as well
-- as the legacy job ever did (insertion order, not guaranteed) — known wart.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.
-- group_concat() → STRING_AGG().

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_ivr_session WHERE event_date = run_date;

INSERT INTO ods.ods_ivr_session
SELECT
  e.session_ref,
  e.client_code,
  TIMESTAMP_MILLIS(MIN(e.event_ms))                                        AS first_event_ts,
  TIMESTAMP_MILLIS(MAX(e.event_ms))                                        AS last_event_ts,
  STRING_AGG(e.menu_path, ' > ')                                           AS menu_path_full,
  CAST(COUNT(*) AS INT64)                                                  AS hops,
  (MAX(CASE WHEN e.menu_path = 'main.agent' THEN 1 ELSE 0 END) = 0)       AS contained_flag,
  MAX(CASE WHEN e.rn_desc = 1 THEN e.key_pressed END)                     AS exit_key,
  DATE(TIMESTAMP_MILLIS(MIN(e.event_ms)))                                  AS event_date
FROM (
  SELECT l.*,
         ROW_NUMBER() OVER (PARTITION BY l.session_ref ORDER BY l.event_ms DESC) AS rn_desc
  FROM staging.stg_file_ivr_logs l
  WHERE l.feed_date = run_date
) e
GROUP BY e.session_ref, e.client_code;
