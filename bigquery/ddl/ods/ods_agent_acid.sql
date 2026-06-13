-- bigquery/ddl/ods/ods_agent_acid.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_agent_acid (...)
--   CLUSTERED BY (agent_id) INTO 8 BUCKETS
--   STORED AS ORC
--   TBLPROPERTIES ('transactional'='true', 'orc.compress'='SNAPPY');
--
-- Conversion notes:
--   - Hive ACID table (ORC transactional) → BigQuery native managed table.
--   - STORED AS ORC, transactional=true, orc.compress dropped — BigQuery uses
--     Capacitor columnar format internally; no user-facing format knob.
--   - Hive CLUSTERED BY (agent_id) INTO 8 BUCKETS → BigQuery CLUSTER BY agent_id.
--   - No PARTITION (small dimension-like table, MERGE target).
--   - No NOT NULL constraints — all columns nullable for MERGE compatibility.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast during load).
--   - Column count: 10 total.

CREATE TABLE IF NOT EXISTS ods.ods_agent_acid (
  agent_id           INT64,
  employee_no        STRING,
  full_name          STRING,
  email              STRING,
  org_unit_id        INT64,
  job_grade          STRING,
  employment_type    STRING,
  hire_ts            TIMESTAMP,
  term_ts            TIMESTAMP,
  status             STRING
)
CLUSTER BY agent_id;
