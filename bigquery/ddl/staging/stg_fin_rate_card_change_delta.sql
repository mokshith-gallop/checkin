-- bigquery/ddl/staging/stg_fin_rate_card_change_delta.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_fin_rate_card_change_delta (...)
--   PARTITIONED BY (extract_ts STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY '|'
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_fin_rate_card_change_delta';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(12,4) → BigQuery NUMERIC(12,4).
--   - Epoch column (change_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive PARTITIONED BY (extract_ts STRING) → renamed to extract_date as DATE column
--     + PARTITION BY extract_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_fin_rate_card_change_delta (
  rate_change_id   INT64,
  rate_card_id     INT64,
  old_rate         NUMERIC(12,4),
  new_rate         NUMERIC(12,4),
  change_reason    STRING,
  op               STRING,
  change_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  extract_date     DATE
)
PARTITION BY extract_date
OPTIONS (description = 'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter');
