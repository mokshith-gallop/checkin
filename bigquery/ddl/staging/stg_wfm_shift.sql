-- bigquery/ddl/staging/stg_wfm_shift.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_shift (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_shift'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch column (created_epoch) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_shift (
  shift_id         INT64,
  shift_code       STRING,
  shift_name       STRING,
  start_hhmm       STRING,
  end_hhmm         STRING,
  overnight_flag   BOOL,
  site_code        STRING,
  created_epoch    INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
