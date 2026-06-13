-- bigquery/ddl/staging/stg_tel_call.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tel_call (...)
--   PARTITIONED BY (load_date STRING)
--   CLUSTERED BY (call_id) INTO 16 BUCKETS
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tel_call'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (start_epoch, answer_epoch, end_epoch) remain INT64 in staging.
--   - Hive CLUSTERED BY (call_id) INTO 16 BUCKETS → BigQuery CLUSTER BY call_id.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 12 source columns + 1 inlined partition column = 13 total.

CREATE TABLE IF NOT EXISTS staging.stg_tel_call (
  call_id            INT64,
  ani                STRING,
  dnis               STRING,
  queue_id           INT64,
  agent_id           INT64,
  program_id         INT64,
  start_epoch        INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  answer_epoch       INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  end_epoch          INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  disposition_code   STRING,
  direction          STRING,
  recording_id       STRING,
  load_date          DATE
)
PARTITION BY load_date
CLUSTER BY call_id;
