-- bigquery/ddl/staging/stg_crm_program.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_program (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_program'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (go_live_ts, updated_ts) remain INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_program (
  program_id         INT64,
  client_id          INT64,
  program_code       STRING,
  program_name       STRING,
  line_of_business   STRING,
  channel_mix        STRING,
  site_code          STRING,
  status             STRING,
  go_live_ts         INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  updated_ts         INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date          DATE
)
PARTITION BY load_date;
