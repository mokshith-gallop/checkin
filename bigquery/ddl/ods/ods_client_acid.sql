-- bigquery/ddl/ods/ods_client_acid.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_client_acid (...)
--   CLUSTERED BY (client_id) INTO 4 BUCKETS
--   STORED AS ORC
--   TBLPROPERTIES ('transactional'='true', 'orc.compress'='SNAPPY');
--
-- Conversion notes:
--   - Hive ACID table (ORC transactional) → BigQuery native managed table.
--   - STORED AS ORC, transactional=true, orc.compress dropped — BigQuery uses
--     Capacitor columnar format internally; no user-facing format knob.
--   - Hive CLUSTERED BY (client_id) INTO 4 BUCKETS → BigQuery CLUSTER BY client_id.
--   - No PARTITION (small dimension-like table, MERGE target).
--   - No NOT NULL constraints — all columns nullable for MERGE compatibility.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast during load).
--   - Column count: 8 total.

CREATE TABLE IF NOT EXISTS ods.ods_client_acid (
  client_id      INT64,
  client_code    STRING,
  client_name    STRING,
  industry       STRING,
  hq_country     STRING,
  status         STRING,
  created_ts     TIMESTAMP,
  updated_ts     TIMESTAMP
)
CLUSTER BY client_id;
