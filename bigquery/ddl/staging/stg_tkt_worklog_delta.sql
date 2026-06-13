-- bigquery/ddl/staging/stg_tkt_worklog_delta.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tkt_worklog_delta (...)
--   PARTITIONED BY (extract_ts STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tkt_worklog_delta';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns: log_ms and change_ms remain INT64 (both epoch MILLISECONDS).
--   - Hive PARTITIONED BY (extract_ts STRING) → renamed to extract_date as DATE column
--     + PARTITION BY extract_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_tkt_worklog_delta (
  worklog_id       INT64,
  ticket_id        INT64,
  agent_id         INT64,
  minutes_logged   INT64,
  log_ms           INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  note             STRING,
  op               STRING,
  change_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  extract_date     DATE
)
PARTITION BY extract_date
OPTIONS (description = 'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter');
