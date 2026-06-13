-- bigquery/ddl/ods/ods_schedule.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_schedule (...)
--   PARTITIONED BY (sched_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in cleanse).
--   - Hive PARTITIONED BY (sched_date STRING) → inlined DATE column +
--     PARTITION BY sched_date.
--   - Column count: 9 source columns + 1 inlined partition column = 10 total.

CREATE TABLE IF NOT EXISTS ods.ods_schedule (
  schedule_id      INT64,
  agent_id         INT64,
  shift_id         INT64,
  shift_code       STRING,
  start_ts         TIMESTAMP,
  end_ts           TIMESTAMP,
  paid_minutes     INT64,
  activity_code    STRING,
  site_code        STRING,
  sched_date       DATE
)
PARTITION BY sched_date;
