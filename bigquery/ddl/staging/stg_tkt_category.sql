-- bigquery/ddl/staging/stg_tkt_category.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tkt_category (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tkt_category'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (created_ms) remains INT64 in staging.
--     This is epoch MILLISECONDS from the ticketing Postgres source.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 5 source columns + 1 inlined partition column = 6 total.

CREATE TABLE IF NOT EXISTS staging.stg_tkt_category (
  category_id      INT64,
  category_code    STRING,
  category_name    STRING,
  sla_hours        INT64,
  created_ms       INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
