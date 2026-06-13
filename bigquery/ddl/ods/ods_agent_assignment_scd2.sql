-- bigquery/ddl/ods/ods_agent_assignment_scd2.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_agent_assignment_scd2 (...)
--   PARTITIONED BY (eff_from_year INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Surrogate key assignment_history_id is STRING — generated via
--     TO_HEX(MD5(CONCAT(CAST(agent_id AS STRING), '|', CAST(program_id AS STRING),
--     '|', CAST(eff_from_ts AS STRING)))).
--   - Hive PARTITIONED BY (eff_from_year INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2026, 1)).
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_agent_assignment_scd2 (
  assignment_history_id   STRING OPTIONS (description = 'Surrogate key: TO_HEX(MD5(CONCAT(CAST(agent_id AS STRING), ''|'', CAST(program_id AS STRING), ''|'', CAST(eff_from_ts AS STRING))))'),
  agent_id                INT64,
  program_id              INT64,
  queue_id                INT64,
  role_on_program         STRING,
  eff_from_ts             TIMESTAMP,
  eff_to_ts               TIMESTAMP,
  is_current              BOOL,
  eff_from_year           INT64
)
PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2026, 1));
