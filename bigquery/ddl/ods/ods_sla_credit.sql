-- bigquery/ddl/ods/ods_sla_credit.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_sla_credit (...)
--   PARTITIONED BY (period_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(12,2) → BigQuery NUMERIC(12,2).
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (delta change_ms cast in merge).
--   - Hive PARTITIONED BY (period_month STRING) → inlined DATE column +
--     PARTITION BY period_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 6 source columns + 1 inlined partition column = 7 total.

CREATE TABLE IF NOT EXISTS ods.ods_sla_credit (
  sla_credit_id    INT64,
  program_id       INT64,
  sla_target_id    INT64,
  credit_amount    NUMERIC(12,2),
  reason           STRING,
  last_change_ts   TIMESTAMP,
  period_month     DATE
)
PARTITION BY period_month;
