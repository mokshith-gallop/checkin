-- bigquery/ddl/dm/dim_org.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_org (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 11 total.

CREATE TABLE IF NOT EXISTS dm.dim_org (
  org_sk         INT64,
  org_unit_id    INT64,
  unit_code      STRING,
  unit_name      STRING,
  unit_type      STRING,
  level1_name    STRING,
  level2_name    STRING,
  level3_name    STRING,
  level4_name    STRING,
  site_code      STRING,
  cost_center    STRING
);
