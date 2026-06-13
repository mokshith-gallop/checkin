-- bigquery/ddl/ods/ods_org_unit.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_org_unit (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in cleanse).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_org_unit (
  org_unit_id      INT64,
  parent_unit_id   INT64,
  unit_code        STRING,
  unit_name        STRING,
  unit_type        STRING,
  site_code        STRING,
  cost_center      STRING,
  created_ts       TIMESTAMP,
  snapshot_date    DATE
)
PARTITION BY snapshot_date;
