-- bigquery/ddl/dm/dim_client.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_client (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 9 total.

CREATE TABLE IF NOT EXISTS dm.dim_client (
  client_sk              INT64,
  client_id              INT64,
  client_code            STRING,
  client_name            STRING,
  industry               STRING,
  hq_country             STRING,
  primary_contact_name   STRING,
  primary_contact_email  STRING,
  status                 STRING
);
