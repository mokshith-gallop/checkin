-- bigquery/ddl/staging/stg_hr_agent.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_hr_agent (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_hr_agent'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (hire_ts, term_ts) remain INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 11 source columns + 1 inlined partition column = 12 total.

CREATE TABLE IF NOT EXISTS staging.stg_hr_agent (
  agent_id           INT64,
  employee_no        STRING,
  first_name         STRING,
  last_name          STRING,
  email              STRING,
  org_unit_id        INT64,
  job_grade          STRING,
  employment_type    STRING,
  hire_ts            INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  term_ts            INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  status             STRING,
  load_date          DATE
)
PARTITION BY load_date;
