-- bigquery/ddl/dm/dim_date.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_date (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small reference/lookup table loaded from datagen parquet).
--   - Column count: 12 total.

CREATE TABLE IF NOT EXISTS dm.dim_date (
  date_key         INT64,
  full_date        STRING,
  day_of_week      INT64,
  day_name         STRING,
  week_of_year     INT64,
  month_no         INT64,
  month_name       STRING,
  quarter_no       INT64,
  year_no          INT64,
  is_weekend       BOOL,
  is_holiday_us    BOOL,
  fiscal_period    STRING
);
