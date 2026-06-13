-- bigquery/ddl/dm/fact_ticket.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_ticket (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1)).
--   - Column count: 11 source columns + 1 inlined partition column = 12 total.

CREATE TABLE IF NOT EXISTS dm.fact_ticket (
  ticket_id            INT64,
  program_sk           INT64,
  category_code        STRING,
  assigned_agent_sk    INT64,
  priority             STRING,
  status               STRING,
  created_ts           TIMESTAMP,
  resolved_ts          TIMESTAMP,
  resolution_minutes   INT64,
  sla_breached_flag    BOOL,
  touch_count          INT64,
  date_key             INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1));
