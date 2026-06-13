-- bigquery/ddl/staging/stg_crm_client_contact.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_crm_client_contact (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_crm_client_contact'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch column (created_ts) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_crm_client_contact (
  contact_id     INT64,
  client_id      INT64,
  full_name      STRING,
  email          STRING,
  phone          STRING,
  role           STRING,
  is_primary     BOOL,
  created_ts     INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date      DATE
)
PARTITION BY load_date;
