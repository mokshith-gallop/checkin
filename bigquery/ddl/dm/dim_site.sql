-- bigquery/ddl/dm/dim_site.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_site (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 6 total.

CREATE TABLE IF NOT EXISTS dm.dim_site (
  site_sk      INT64,
  site_code    STRING,
  site_name    STRING,
  region       STRING,
  country      STRING,
  timezone     STRING
);
