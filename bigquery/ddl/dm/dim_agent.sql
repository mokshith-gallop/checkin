-- bigquery/ddl/dm/dim_agent.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.dim_agent (...)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - No partition (small dimension table).
--   - Column count: 12 total.

CREATE TABLE IF NOT EXISTS dm.dim_agent (
  agent_sk           INT64,
  agent_id           INT64,
  employee_no        STRING,
  full_name          STRING,
  job_grade          STRING,
  employment_type    STRING,
  org_unit_id        INT64,
  team_name          STRING,
  site_code          STRING,
  status             STRING,
  hire_date_key      INT64,
  is_current         BOOL
);
