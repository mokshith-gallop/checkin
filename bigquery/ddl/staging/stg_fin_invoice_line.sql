-- bigquery/ddl/staging/stg_fin_invoice_line.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_fin_invoice_line (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_fin_invoice_line'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive DECIMAL(12,2) → BigQuery NUMERIC(12,2); DECIMAL(12,4) → NUMERIC(12,4);
--     DECIMAL(14,2) → NUMERIC(14,2).
--   - Epoch column (created_ms) remains INT64 in staging.
--     This is epoch MILLISECONDS from the finance SQL Server source.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_fin_invoice_line (
  invoice_line_id    INT64,
  invoice_id         INT64,
  contract_line_id   INT64,
  qty                NUMERIC(12,2),
  unit_rate          NUMERIC(12,4),
  line_amount        NUMERIC(14,2),
  adjustment_flag    BOOL,
  created_ms         INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  load_date          DATE
)
PARTITION BY load_date;
