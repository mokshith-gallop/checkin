-- bigquery/ddl/staging/stg_crm_contract.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_contract (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_contract'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64 (identical 64-bit signed integer range).
--   - Hive STRING  → BigQuery STRING (direct map).
--   - Oracle string-date columns (start_dt, end_dt, signed_dt) kept as STRING;
--     semantic parsing to TIMESTAMP is the ODS cleanse layer's job
--     (see 10-cleanse-contract.sql → PARSE_TIMESTAMP).
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--     Type changed from STRING to DATE because BigQuery requires DATE/TIMESTAMP/DATETIME/INT64
--     for partitioning, and the downstream cleanse script already compares load_date to a DATE.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_contract (
  contract_id    INT64,
  client_id      INT64,
  program_id     INT64,
  contract_no    STRING,
  start_dt       STRING OPTIONS (description = 'Oracle string YYYYMMDDHH24MISS (legacy)'),
  end_dt         STRING OPTIONS (description = 'Oracle string YYYYMMDDHH24MISS (legacy)'),
  billing_model  STRING,
  currency       STRING,
  signed_dt      STRING OPTIONS (description = 'Oracle string YYYYMMDDHH24MISS (legacy)'),
  status         STRING,
  load_date      DATE
)
PARTITION BY load_date;
