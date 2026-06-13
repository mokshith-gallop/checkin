-- bigquery/ddl/ods/ods_shift_swap.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_shift_swap (...)
--   PARTITIONED BY (swap_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (delta change_ms cast in merge).
--   - Hive PARTITIONED BY (swap_month STRING) → inlined DATE column +
--     PARTITION BY swap_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS ods.ods_shift_swap (
  swap_id              INT64,
  requesting_agent_id  INT64,
  accepting_agent_id   INT64,
  schedule_id          INT64,
  swap_date            STRING,
  status               STRING,
  last_change_ts       TIMESTAMP,
  swap_month           DATE
)
PARTITION BY swap_month;
