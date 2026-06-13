-- bigquery/ddl/dm/dim_queue.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_queue (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 7 total.

CREATE TABLE IF NOT EXISTS dm.dim_queue (
  queue_sk       INT64,
  queue_id       INT64,
  queue_code     STRING,
  queue_name     STRING,
  program_id     INT64,
  media_type     STRING,
  priority       INT64
);
