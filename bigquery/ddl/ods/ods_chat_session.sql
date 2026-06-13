-- bigquery/ddl/ods/ods_chat_session.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_chat_session (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch millis cast in cleanse).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS ods.ods_chat_session (
  chat_ref                 STRING,
  client_code              STRING,
  queue_code               STRING,
  agent_email              STRING,
  started_ts               TIMESTAMP,
  ended_ts                 TIMESTAMP,
  message_count            INT64,
  agent_message_count      INT64,
  customer_message_count   INT64,
  first_response_seconds   INT64,
  event_date               DATE
)
PARTITION BY event_date;
