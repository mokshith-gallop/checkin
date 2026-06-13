-- bigquery/ddl/dm/fact_billing_line.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_billing_line (...)
--   PARTITIONED BY (period_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(12,2) → BigQuery NUMERIC(12,2); DECIMAL(12,4) → NUMERIC(12,4);
--     DECIMAL(14,2) → NUMERIC(14,2).
--   - Hive PARTITIONED BY (period_month STRING) → inlined DATE column +
--     PARTITION BY period_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS dm.fact_billing_line (
  invoice_line_id    INT64,
  invoice_id         INT64,
  client_sk          INT64,
  program_sk         INT64,
  service_code       STRING,
  qty                NUMERIC(12,2),
  unit_rate          NUMERIC(12,4),
  line_amount        NUMERIC(14,2),
  adjustment_flag    BOOL,
  invoice_status     STRING,
  period_month       DATE
)
PARTITION BY period_month;
