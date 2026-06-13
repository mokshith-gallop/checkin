-- bigquery/ddl/dm/fact_queue_interval.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_queue_interval (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Hive DECIMAL(8,2) → BigQuery NUMERIC(8,2).
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000)).
--   - Column count: 9 source columns + 1 inlined partition column = 10 total.

CREATE TABLE IF NOT EXISTS dm.fact_queue_interval (
  queue_sk               INT64,
  interval_start_ts      TIMESTAMP,
  offered                INT64,
  answered               INT64,
  abandoned              INT64,
  answered_in_sl         INT64,
  sl_threshold_sec       INT64,
  avg_speed_answer_sec   NUMERIC(8,2),
  avg_handle_sec         NUMERIC(8,2),
  date_key               INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000));
