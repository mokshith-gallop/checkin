-- bigquery/ddl/dm/fact_adherence_daily.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_adherence_daily (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2).
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000)).
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS dm.fact_adherence_daily (
  agent_sk             INT64,
  scheduled_minutes    INT64,
  worked_minutes       INT64,
  exception_minutes    INT64,
  timeoff_minutes      INT64,
  adherence_pct        NUMERIC(5,2),
  occupancy_pct        NUMERIC(5,2),
  date_key             INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000));
