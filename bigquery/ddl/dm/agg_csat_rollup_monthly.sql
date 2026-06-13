-- bigquery/ddl/dm/agg_csat_rollup_monthly.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_csat_rollup_monthly (...)
--   PARTITIONED BY (period_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2).
--   - Hive PARTITIONED BY (period_month STRING) → inlined DATE column +
--     PARTITION BY period_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS dm.agg_csat_rollup_monthly (
  client_sk        INT64,
  program_sk       INT64,
  site_code        STRING,
  surveys          INT64,
  avg_csat         NUMERIC(5,2),
  pct_promoters    NUMERIC(5,2),
  pct_detractors   NUMERIC(5,2),
  grouping_id      INT64,
  period_month     DATE
)
PARTITION BY period_month;
