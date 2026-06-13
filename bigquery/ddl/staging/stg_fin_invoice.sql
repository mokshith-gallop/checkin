-- bigquery/ddl/staging/stg_fin_invoice.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_fin_invoice (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_fin_invoice'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(14,2) → BigQuery NUMERIC(14,2).
--   - issued_ts_sec and due_ts_sec are LYING columns: names say "seconds" but
--     values are actually MILLISECONDS. Kept as INT64 in staging with warning
--     description. See EPOCH-POLICY.md for full details.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS staging.stg_fin_invoice (
  invoice_id       INT64,
  invoice_no       STRING,
  client_id        INT64,
  program_id       INT64,
  period_month     STRING,
  issued_ts_sec    INT64 OPTIONS (description = 'WARNING: column name says seconds but VALUES ARE MILLISECONDS. All consumers divide by 1000. See EPOCH-POLICY.md.'),
  due_ts_sec       INT64 OPTIONS (description = 'WARNING: column name says seconds but VALUES ARE MILLISECONDS. All consumers divide by 1000. See EPOCH-POLICY.md.'),
  currency         STRING,
  total_amount     NUMERIC(14,2),
  status           STRING,
  load_date        DATE
)
PARTITION BY load_date;
