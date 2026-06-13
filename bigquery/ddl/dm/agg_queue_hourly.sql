-- bigquery/ddl/dm/agg_queue_hourly.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_queue_hourly (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2); DECIMAL(7,2) → NUMERIC(7,2).
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1)).
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS dm.agg_queue_hourly (
  queue_sk               INT64,
  hour_of_day            INT64,
  offered                INT64,
  answered               INT64,
  abandoned              INT64,
  sl_pct                 NUMERIC(5,2),
  forecast_volume        INT64,
  volume_variance_pct    NUMERIC(7,2),
  date_key               INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1));
