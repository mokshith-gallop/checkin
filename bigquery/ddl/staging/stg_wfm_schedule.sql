-- bigquery/ddl/staging/stg_wfm_schedule.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_schedule (...)
--   PARTITIONED BY (load_date STRING, site_code STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_schedule'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (start_epoch, end_epoch) remain INT64 in staging.
--   - Hive multi-column partition (load_date, site_code): BigQuery supports only a single
--     partition column. load_date inlined as DATE + PARTITION BY load_date;
--     site_code demoted to a regular STRING column and used as CLUSTER BY key.
--   - Column count: 8 source columns + 2 inlined partition columns = 10 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_schedule (
  schedule_id      INT64,
  agent_id         INT64,
  shift_id         INT64,
  sched_date       STRING,
  start_epoch      INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  end_epoch        INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  paid_minutes     INT64,
  activity_code    STRING,
  load_date        DATE,
  site_code        STRING
)
PARTITION BY load_date
CLUSTER BY site_code;
