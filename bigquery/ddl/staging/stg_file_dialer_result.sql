-- bigquery/ddl/staging/stg_file_dialer_result.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_dialer_result (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   STORED AS RCFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_dialer_result';
--
-- Conversion notes:
--   - EXTERNAL, STORED AS RCFILE, LOCATION dropped (BigQuery managed table).
--   - Source data is converted from RCFile to Parquet/JSON before BQ load.
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (attempt_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_dialer_result (
  attempt_id       STRING,
  campaign_code    STRING,
  phone_hash       STRING,
  agent_id         INT64,
  attempt_ms       INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  result_code      STRING,
  talk_seconds     INT64,
  client_code      STRING,
  feed_date        DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive RCFile — converted to Parquet/JSON for BQ load');
