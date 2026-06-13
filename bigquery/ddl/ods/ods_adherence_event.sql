-- bigquery/ddl/ods/ods_adherence_event.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_adherence_event (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in cleanse).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_adherence_event (
  adherence_event_id   INT64,
  agent_id             INT64,
  schedule_id          INT64,
  exception_type       STRING,
  start_ts             TIMESTAMP,
  end_ts               TIMESTAMP,
  exception_minutes    INT64,
  approved_flag        BOOL,
  event_date           DATE
)
PARTITION BY event_date;
