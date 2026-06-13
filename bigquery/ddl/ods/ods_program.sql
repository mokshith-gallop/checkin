-- bigquery/ddl/ods/ods_program.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_program (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (ODS layer — epochs already cast).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date. Type changed from STRING to DATE.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS ods.ods_program (
  program_id         INT64,
  client_id          INT64,
  program_code       STRING,
  program_name       STRING,
  line_of_business   STRING,
  channel_mix        STRING,
  site_code          STRING,
  status             STRING,
  go_live_ts         TIMESTAMP,
  updated_ts         TIMESTAMP,
  snapshot_date      DATE
)
PARTITION BY snapshot_date;
