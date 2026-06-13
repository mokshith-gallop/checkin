-- bigquery/ddl/staging/stg_file_chat_transcripts.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_chat_transcripts (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_chat_transcripts'
--   TBLPROPERTIES ('ignore.malformed.json'='true');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT SERDE (JsonSerDe), STORED AS TEXTFILE, LOCATION, TBLPROPERTIES
--     dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive ARRAY<STRUCT<sender:STRING,ts_ms:BIGINT,text:STRING>> →
--     BigQuery ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>.
--   - Hive MAP<STRING,STRING> → BigQuery JSON. Query individual keys with
--     JSON_VALUE(metadata, '$.key_name').
--   - Epoch columns (started_ms, ended_ms) remain INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_chat_transcripts (
  chat_ref       STRING,
  queue_code     STRING,
  agent_email    STRING,
  started_ms     INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  ended_ms       INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  messages       ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>,
  metadata       JSON OPTIONS (description = 'Hive MAP<STRING,STRING> represented as JSON. Query individual keys with JSON_VALUE(metadata, "$.key_name").'),
  client_code    STRING,
  feed_date      DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive JsonSerDe — loaded as NEWLINE_DELIMITED_JSON');
