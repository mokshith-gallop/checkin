-- bigquery/ddl/ods/ods_callback_request.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_callback_request (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in merge).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS ods.ods_callback_request (
  callback_id      INT64,
  call_id          INT64,
  queue_id         INT64,
  requested_ts     TIMESTAMP,
  scheduled_ts     TIMESTAMP,
  completed_flag   BOOL,
  last_change_ts   TIMESTAMP,
  event_date       DATE
)
PARTITION BY event_date;
