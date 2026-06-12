-- 23-cleanse-dialer-attempt.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_dialer_result
-- writes: ods.ods_dialer_attempt

-- Cleanse staging.stg_file_dialer_result -> ods.ods_dialer_attempt: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_dialer_attempt WHERE event_date = run_date;

INSERT INTO ods.ods_dialer_attempt
SELECT
  s.attempt_id                                                           AS attempt_id,
  s.client_code                                                          AS client_code,
  s.campaign_code                                                        AS campaign_code,
  s.agent_id                                                             AS agent_id,
  TIMESTAMP_MILLIS(s.attempt_ms)                                         AS attempt_ts,
  s.result_code                                                          AS result_code,
  (s.result_code = 'CONNECT')                                            AS connected_flag,
  s.talk_seconds                                                         AS talk_seconds,
  DATE(TIMESTAMP_MILLIS(s.attempt_ms))                                   AS event_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.attempt_id ORDER BY s.attempt_ms DESC) AS rn
  FROM staging.stg_file_dialer_result s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
