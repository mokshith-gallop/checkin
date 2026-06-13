-- bigquery/ddl/dm/agg_agent_weekly.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_agent_weekly (...)
--   PARTITIONED BY (week_start_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(8,2) → BigQuery NUMERIC(8,2); DECIMAL(5,2) → NUMERIC(5,2).
--   - Hive PARTITIONED BY (week_start_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(week_start_key, GENERATE_ARRAY(20200101, 20260101, 10000)).
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS dm.agg_agent_weekly (
  agent_sk               INT64,
  site_code              STRING,
  days_worked            INT64,
  interactions_handled   INT64,
  avg_handle_seconds     NUMERIC(8,2),
  adherence_pct          NUMERIC(5,2),
  occupancy_pct          NUMERIC(5,2),
  week_start_key         INT64
)
PARTITION BY RANGE_BUCKET(week_start_key, GENERATE_ARRAY(20200101, 20260101, 10000));
