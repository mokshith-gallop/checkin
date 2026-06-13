-- bigquery/ddl/staging/stg_tel_disposition_code.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tel_disposition_code (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tel_disposition_code'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive STRING  → BigQuery STRING.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch column (created_epoch) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 5 source columns + 1 inlined partition column = 6 total.

CREATE TABLE IF NOT EXISTS staging.stg_tel_disposition_code (
  disposition_code   STRING,
  disposition_desc   STRING,
  category           STRING,
  billable_flag      BOOL,
  created_epoch      INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date          DATE
)
PARTITION BY load_date;
