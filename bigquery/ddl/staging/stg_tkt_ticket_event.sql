-- bigquery/ddl/staging/stg_tkt_ticket_event.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tkt_ticket_event (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tkt_ticket_event'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (event_ms) remains INT64 in staging.
--     This is epoch MILLISECONDS from the ticketing Postgres source.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_tkt_ticket_event (
  ticket_event_id    INT64,
  ticket_id          INT64,
  event_type         STRING,
  event_ms           INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  actor_agent_id     INT64,
  old_value          STRING,
  new_value          STRING,
  load_date          DATE
)
PARTITION BY load_date;
