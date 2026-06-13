-- bigquery/ddl/ods/ods_ticket_worklog.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_ticket_worklog (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (delta change_ms cast in merge).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS ods.ods_ticket_worklog (
  worklog_id       INT64,
  ticket_id        INT64,
  agent_id         INT64,
  minutes_logged   INT64,
  log_ts           TIMESTAMP,
  note             STRING,
  last_change_ts   TIMESTAMP,
  event_date       DATE
)
PARTITION BY event_date;
