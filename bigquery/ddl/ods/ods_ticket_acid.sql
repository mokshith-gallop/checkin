-- bigquery/ddl/ods/ods_ticket_acid.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_ticket_acid (...)
--   CLUSTERED BY (ticket_id) INTO 8 BUCKETS
--   STORED AS ORC
--   TBLPROPERTIES ('transactional'='true', 'orc.compress'='SNAPPY');
--
-- Conversion notes:
--   - Hive ACID table (ORC transactional) → BigQuery native managed table.
--   - STORED AS ORC, transactional=true, orc.compress dropped — BigQuery uses
--     Capacitor columnar format internally; no user-facing format knob.
--   - Hive CLUSTERED BY (ticket_id) INTO 8 BUCKETS → BigQuery CLUSTER BY ticket_id.
--   - No PARTITION (small table, MERGE target).
--   - No NOT NULL constraints — all columns nullable for MERGE compatibility.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch millis cast during load).
--   - Column count: 10 total.

CREATE TABLE IF NOT EXISTS ods.ods_ticket_acid (
  ticket_id          INT64,
  ticket_no          STRING,
  program_id         INT64,
  category_id        INT64,
  assigned_agent_id  INT64,
  priority           STRING,
  status             STRING,
  created_ts         TIMESTAMP,
  updated_ts         TIMESTAMP,
  resolved_ts        TIMESTAMP
)
CLUSTER BY ticket_id;
