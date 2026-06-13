-- bigquery/ddl/ods/ods_call.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_call (...)
--   PARTITIONED BY (call_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in cleanse).
--   - Hive PARTITIONED BY (call_date STRING) → inlined DATE column +
--     PARTITION BY call_date.
--   - Column count: 15 source columns + 1 inlined partition column = 16 total.

CREATE TABLE IF NOT EXISTS ods.ods_call (
  call_id            INT64,
  queue_id           INT64,
  agent_id           INT64,
  program_id         INT64,
  direction          STRING,
  start_ts           TIMESTAMP,
  answer_ts          TIMESTAMP,
  end_ts             TIMESTAMP,
  ring_seconds       INT64,
  talk_seconds       INT64,
  hold_seconds       INT64,
  acw_seconds        INT64,
  abandoned_flag     BOOL,
  disposition_code   STRING,
  recording_id       STRING,
  call_date          DATE
)
PARTITION BY call_date;
