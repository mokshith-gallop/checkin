-- bigquery/ddl/staging/stg_tel_queue.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tel_queue (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tel_queue'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (created_epoch) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_tel_queue (
  queue_id         INT64,
  queue_code       STRING,
  queue_name       STRING,
  program_id       INT64,
  media_type       STRING,
  priority         INT64,
  created_epoch    INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
