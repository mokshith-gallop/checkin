-- bigquery/ddl/dm/dim_program.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_program (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 11 total.

CREATE TABLE IF NOT EXISTS dm.dim_program (
  program_sk         INT64,
  program_id         INT64,
  program_code       STRING,
  program_name       STRING,
  client_id          INT64,
  line_of_business   STRING,
  channel_mix        STRING,
  site_code          STRING,
  billing_model      STRING,
  status             STRING,
  go_live_date_key   INT64
);
