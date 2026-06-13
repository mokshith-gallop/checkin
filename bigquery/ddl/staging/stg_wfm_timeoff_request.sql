-- bigquery/ddl/staging/stg_wfm_timeoff_request.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_wfm_timeoff_request (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_wfm_timeoff_request'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (request_epoch) remains INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_wfm_timeoff_request (
  timeoff_id       INT64,
  agent_id         INT64,
  request_epoch    INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  start_date       STRING,
  end_date         STRING,
  timeoff_type     STRING,
  status           STRING,
  load_date        DATE
)
PARTITION BY load_date;
