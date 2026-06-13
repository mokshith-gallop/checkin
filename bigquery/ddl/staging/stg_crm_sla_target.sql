-- bigquery/ddl/staging/stg_crm_sla_target.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_sla_target (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_sla_target'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(10,4) → BigQuery NUMERIC(10,4); DECIMAL(5,2) → NUMERIC(5,2).
--   - Epoch column (effective_ts) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_sla_target (
  sla_target_id    INT64,
  program_id       INT64,
  queue_id         INT64,
  metric_code      STRING,
  target_value     NUMERIC(10,4),
  penalty_pct      NUMERIC(5,2),
  effective_ts     INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
