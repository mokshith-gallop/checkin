-- bigquery/ddl/staging/stg_tkt_ticket.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tkt_ticket (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tkt_ticket'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (created_ms, updated_ms) remain INT64 in staging.
--     These are epoch MILLISECONDS from the ticketing Postgres source.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 11 source columns + 1 inlined partition column = 12 total.

CREATE TABLE IF NOT EXISTS staging.stg_tkt_ticket (
  ticket_id            INT64,
  ticket_no            STRING,
  program_id           INT64,
  category_id          INT64,
  opened_by_agent_id   INT64,
  assigned_agent_id    INT64,
  interaction_ref      STRING,
  priority             STRING,
  status               STRING,
  created_ms           INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  updated_ms           INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  load_date            DATE
)
PARTITION BY load_date;
