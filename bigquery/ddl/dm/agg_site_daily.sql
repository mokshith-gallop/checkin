-- bigquery/ddl/dm/agg_site_daily.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.agg_site_daily (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(8,2) → BigQuery NUMERIC(8,2); DECIMAL(5,2) → NUMERIC(5,2).
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000)).
--   - Column count: 6 source columns + 1 inlined partition column = 7 total.

CREATE TABLE IF NOT EXISTS dm.agg_site_daily (
  site_code            STRING,
  agents_active        INT64,
  interactions         INT64,
  avg_handle_seconds   NUMERIC(8,2),
  sl_pct               NUMERIC(5,2),
  adherence_pct        NUMERIC(5,2),
  date_key             INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000));
