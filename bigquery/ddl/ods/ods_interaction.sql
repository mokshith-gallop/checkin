-- bigquery/ddl/ods/ods_interaction.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_interaction (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (conformed from multiple channel sources).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 12 source columns + 1 inlined partition column = 13 total.

CREATE TABLE IF NOT EXISTS ods.ods_interaction (
  interaction_id     STRING,
  channel            STRING,
  client_code        STRING,
  program_id         INT64,
  queue_id           INT64,
  agent_id           INT64,
  customer_ref       STRING,
  start_ts           TIMESTAMP,
  end_ts             TIMESTAMP,
  handle_seconds     INT64,
  resolved_flag      BOOL,
  source_system      STRING,
  event_date         DATE
)
PARTITION BY event_date;
