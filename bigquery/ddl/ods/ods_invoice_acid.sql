-- bigquery/ddl/ods/ods_invoice_acid.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_invoice_acid (...)
--   CLUSTERED BY (invoice_id) INTO 4 BUCKETS
--   STORED AS ORC
--   TBLPROPERTIES ('transactional'='true', 'orc.compress'='SNAPPY');
--
-- Conversion notes:
--   - Hive ACID table (ORC transactional) → BigQuery native managed table.
--   - STORED AS ORC, transactional=true, orc.compress dropped — BigQuery uses
--     Capacitor columnar format internally; no user-facing format knob.
--   - Hive CLUSTERED BY (invoice_id) INTO 4 BUCKETS → BigQuery CLUSTER BY invoice_id.
--   - No PARTITION (small table, MERGE target).
--   - No NOT NULL constraints — all columns nullable for MERGE compatibility.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(14,2) → BigQuery NUMERIC(14,2).
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (millis-in-sec-column trap resolved during load).
--   - Column count: 10 total.

CREATE TABLE IF NOT EXISTS ods.ods_invoice_acid (
  invoice_id       INT64,
  invoice_no       STRING,
  client_id        INT64,
  program_id       INT64,
  period_month     STRING,
  issued_ts        TIMESTAMP,
  due_ts           TIMESTAMP,
  currency         STRING,
  total_amount     NUMERIC(14,2),
  status           STRING
)
CLUSTER BY invoice_id;
