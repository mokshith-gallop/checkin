-- bigquery/ddl/staging/stg_hr_org_unit.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_hr_org_unit (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_hr_org_unit'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (created_ts) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_hr_org_unit (
  org_unit_id      INT64,
  parent_unit_id   INT64,
  unit_code        STRING,
  unit_name        STRING,
  unit_type        STRING,
  site_code        STRING,
  cost_center      STRING,
  created_ts       INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
