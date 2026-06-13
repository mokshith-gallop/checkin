-- bigquery/ddl/staging/stg_crm_contract_line.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_contract_line (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_contract_line'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DECIMAL(12,4) → BigQuery NUMERIC(12,4); DECIMAL(12,2) → NUMERIC(12,2).
--   - Oracle string-date column (effective_dt) kept as STRING in staging;
--     semantic parsing to TIMESTAMP is the ODS cleanse layer's job.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_contract_line (
  contract_line_id   INT64,
  contract_id        INT64,
  line_no            INT64,
  service_code       STRING,
  uom                STRING,
  unit_rate          NUMERIC(12,4),
  min_commit         NUMERIC(12,2),
  effective_dt       STRING OPTIONS (description = 'Oracle string YYYYMMDDHH24MISS (legacy)'),
  load_date          DATE
)
PARTITION BY load_date;
