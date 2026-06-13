-- bigquery/ddl/staging/stg_hr_employment_event.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_hr_employment_event (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_hr_employment_event'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (event_ts) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_hr_employment_event (
  event_id           INT64,
  agent_id           INT64,
  event_type         STRING,
  event_ts           INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  from_org_unit_id   INT64,
  to_org_unit_id     INT64,
  reason_code        STRING,
  load_date          DATE
)
PARTITION BY load_date;
