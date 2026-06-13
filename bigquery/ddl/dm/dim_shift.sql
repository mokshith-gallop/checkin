-- bigquery/ddl/dm/dim_shift.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_shift (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 8 total.

CREATE TABLE IF NOT EXISTS dm.dim_shift (
  shift_sk         INT64,
  shift_id         INT64,
  shift_code       STRING,
  shift_name       STRING,
  start_hhmm       STRING,
  end_hhmm         STRING,
  overnight_flag   BOOL,
  site_code        STRING
);
