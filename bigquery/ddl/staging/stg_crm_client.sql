-- bigquery/ddl/staging/stg_crm_client.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_client (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_client'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (created_ts, updated_ts) remain INT64 in staging;
--     semantic conversion to TIMESTAMP is the ODS cleanse layer's job.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--     Type changed from STRING to DATE because BigQuery requires DATE/TIMESTAMP/DATETIME/INT64
--     for partitioning.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_client (
  client_id      INT64,
  client_code    STRING,
  client_name    STRING,
  industry       STRING,
  hq_country     STRING,
  status         STRING,
  created_ts     INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  updated_ts     INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date      DATE
)
PARTITION BY load_date;
