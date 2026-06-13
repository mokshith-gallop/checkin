-- bigquery/ddl/ods/ods_queue.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_queue (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in cleanse).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS ods.ods_queue (
  queue_id         INT64,
  queue_code       STRING,
  queue_name       STRING,
  program_id       INT64,
  media_type       STRING,
  priority         INT64,
  created_ts       TIMESTAMP,
  snapshot_date    DATE
)
PARTITION BY snapshot_date;
