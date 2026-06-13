-- bigquery/ddl/staging/stg_tel_callback_request_delta.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tel_callback_request_delta (...)
--   PARTITIONED BY (extract_ts STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tel_callback_request_delta';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch columns: requested_epoch, scheduled_epoch remain INT64 (epoch SECONDS);
--     change_ms remains INT64 (epoch MILLISECONDS).
--   - Hive PARTITIONED BY (extract_ts STRING) → renamed to extract_date as DATE column
--     + PARTITION BY extract_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_tel_callback_request_delta (
  callback_id        INT64,
  call_id            INT64,
  queue_id           INT64,
  requested_epoch    INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  scheduled_epoch    INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  completed_flag     BOOL,
  op                 STRING,
  change_ms          INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  extract_date       DATE
)
PARTITION BY extract_date
OPTIONS (description = 'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter');
