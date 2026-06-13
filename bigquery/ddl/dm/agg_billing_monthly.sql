-- bigquery/ddl/dm/agg_billing_monthly.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_billing_monthly (...)
--   PARTITIONED BY (period_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(14,2) → BigQuery NUMERIC(14,2); DECIMAL(12,2) → NUMERIC(12,2).
--   - Hive PARTITIONED BY (period_month STRING) → inlined DATE column +
--     PARTITION BY period_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 6 source columns + 1 inlined partition column = 7 total.

CREATE TABLE IF NOT EXISTS dm.agg_billing_monthly (
  client_sk            INT64,
  program_sk           INT64,
  billed_amount        NUMERIC(14,2),
  sla_credit_amount    NUMERIC(12,2),
  telco_cost_amount    NUMERIC(12,2),
  net_revenue          NUMERIC(14,2),
  period_month         DATE
)
PARTITION BY period_month;
