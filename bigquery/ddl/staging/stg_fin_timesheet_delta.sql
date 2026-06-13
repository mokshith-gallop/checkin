-- bigquery/ddl/staging/stg_fin_timesheet_delta.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_fin_timesheet_delta (...)
--   PARTITIONED BY (extract_ts STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_fin_timesheet_delta';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch column (change_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive PARTITIONED BY (extract_ts STRING) → renamed to extract_date as DATE column
--     + PARTITION BY extract_date. BigQuery requires DATE/TIMESTAMP/DATETIME/INT64 for
--     partitioning; the STRING extract_ts is replaced with a DATE.
--   - Column count: 9 source columns + 1 inlined partition column = 10 total.

CREATE TABLE IF NOT EXISTS staging.stg_fin_timesheet_delta (
  timesheet_id        INT64,
  agent_id            INT64,
  work_date           STRING,
  program_id          INT64,
  billable_minutes    INT64,
  nonbillable_minutes INT64,
  approved_flag       BOOL,
  op                  STRING,
  change_ms           INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  extract_date        DATE
)
PARTITION BY extract_date
OPTIONS (description = 'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter');
