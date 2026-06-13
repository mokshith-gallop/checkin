-- bigquery/ddl/dm/dim_disposition.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_disposition (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 5 total.

CREATE TABLE IF NOT EXISTS dm.dim_disposition (
  disposition_sk     INT64,
  disposition_code   STRING,
  disposition_desc   STRING,
  category           STRING,
  billable_flag      BOOL
);
