-- bigquery/ddl/staging/stg_tel_call_segment.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_tel_call_segment (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_tel_call_segment'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (start_epoch, end_epoch) remain INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_tel_call_segment (
  segment_id       INT64,
  call_id          INT64,
  segment_no       INT64,
  segment_type     STRING,
  start_epoch      INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  end_epoch        INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  agent_id         INT64,
  load_date        DATE
)
PARTITION BY load_date;
