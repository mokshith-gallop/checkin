-- bigquery/ddl/dm/agg_program_monthly.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_program_monthly (...)
--   PARTITIONED BY (period_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(8,2) → BigQuery NUMERIC(8,2); DECIMAL(5,2) → NUMERIC(5,2);
--     DECIMAL(14,2) → NUMERIC(14,2).
--   - Hive PARTITIONED BY (period_month STRING) → inlined DATE column +
--     PARTITION BY period_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS dm.agg_program_monthly (
  client_sk            INT64,
  program_sk           INT64,
  line_of_business     STRING,
  interactions         INT64,
  avg_handle_seconds   NUMERIC(8,2),
  avg_csat             NUMERIC(5,2),
  billed_amount        NUMERIC(14,2),
  grouping_level       INT64,
  period_month         DATE
)
PARTITION BY period_month;
