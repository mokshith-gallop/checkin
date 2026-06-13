-- bigquery/ddl/staging/stg_wfm_adherence_event.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_adherence_event (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_adherence_event'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch columns (start_epoch, end_epoch) remain INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_adherence_event (
  adherence_event_id   INT64,
  agent_id             INT64,
  schedule_id          INT64,
  exception_type       STRING,
  start_epoch          INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  end_epoch            INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  approved_flag        BOOL,
  load_date            DATE
)
PARTITION BY load_date;
