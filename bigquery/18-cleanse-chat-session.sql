-- 18-cleanse-chat-session.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_chat_transcripts
-- writes: ods.ods_chat_session

-- Chat transcripts arrive as JSON with a nested messages ARRAY<STRUCT<...>>.
-- Impala nested-collection syntax (t, t.messages m) converted to
-- CROSS JOIN UNNEST(t.messages) AS m per BigQuery standard.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_chat_session WHERE event_date = run_date;

INSERT INTO ods.ods_chat_session
SELECT
  t.chat_ref,
  t.client_code,
  t.queue_code,
  t.agent_email,
  TIMESTAMP_MILLIS(t.started_ms)                                        AS started_ts,
  TIMESTAMP_MILLIS(t.ended_ms)                                          AS ended_ts,
  CAST(COUNT(m.sender) AS INT64)                                        AS message_count,
  CAST(SUM(CASE WHEN m.sender = 'AGENT'    THEN 1 ELSE 0 END) AS INT64) AS agent_message_count,
  CAST(SUM(CASE WHEN m.sender = 'CUSTOMER' THEN 1 ELSE 0 END) AS INT64) AS customer_message_count,
  CAST((MIN(CASE WHEN m.sender = 'AGENT' THEN m.ts_ms END) - t.started_ms) / 1000 AS INT64)
                                                                        AS first_response_seconds,
  DATE(TIMESTAMP_MILLIS(t.started_ms))                                  AS event_date
FROM staging.stg_file_chat_transcripts t
CROSS JOIN UNNEST(t.messages) AS m
WHERE t.feed_date = run_date
GROUP BY t.chat_ref, t.client_code, t.queue_code, t.agent_email,
         t.started_ms, t.ended_ms;
