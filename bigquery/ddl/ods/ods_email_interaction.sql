-- bigquery/ddl/ods/ods_email_interaction.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_email_interaction (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch millis cast in cleanse).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 9 source columns + 1 inlined partition column = 10 total.

CREATE TABLE IF NOT EXISTS ods.ods_email_interaction (
  email_ref            STRING,
  client_code          STRING,
  mailbox              STRING,
  agent_email          STRING,
  received_ts          TIMESTAMP,
  first_reply_ts       TIMESTAMP,
  resolved_ts          TIMESTAMP,
  reply_sla_minutes    INT64,
  subject_category     STRING,
  event_date           DATE
)
PARTITION BY event_date;
