-- bigquery/ddl/staging/stg_wfm_shift_swap_delta.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_shift_swap_delta (...)
--   PARTITIONED BY (extract_ts STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_shift_swap_delta';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (change_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive PARTITIONED BY (extract_ts STRING) → renamed to extract_date as DATE column
--     + PARTITION BY extract_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_shift_swap_delta (
  swap_id              INT64,
  requesting_agent_id  INT64,
  accepting_agent_id   INT64,
  schedule_id          INT64,
  swap_date            STRING,
  status               STRING,
  op                   STRING,
  change_ms            INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  extract_date         DATE
)
PARTITION BY extract_date
OPTIONS (description = 'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter');
