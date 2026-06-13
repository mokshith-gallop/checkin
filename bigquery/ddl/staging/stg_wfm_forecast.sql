-- bigquery/ddl/staging/stg_wfm_forecast.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_forecast (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_forecast'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DECIMAL(8,2) → BigQuery NUMERIC(8,2).
--   - Epoch column (interval_start_epoch) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 6 source columns + 1 inlined partition column = 7 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_forecast (
  forecast_id            INT64,
  queue_id               INT64,
  interval_start_epoch   INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  forecast_volume        INT64,
  forecast_aht_sec       INT64,
  required_fte           NUMERIC(8,2),
  load_date              DATE
)
PARTITION BY load_date;
