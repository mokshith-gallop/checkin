-- bigquery/ddl/staging/stg_file_interaction_export.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_interaction_export (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_interaction_export'
--   TBLPROPERTIES ('skip.header.line.count'='1');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION, TBLPROPERTIES dropped
--     (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (start_ms, end_ms) remain INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): BigQuery supports only a single
--     partition column. feed_date inlined as DATE + PARTITION BY feed_date;
--     client_code demoted to a regular STRING column and used as CLUSTER BY key.
--   - Column count: 8 source columns + 2 inlined partition columns = 10 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_interaction_export (
  interaction_ref        STRING,
  channel                STRING,
  client_interaction_id  STRING,
  agent_email            STRING,
  start_ms               INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  end_ms                 INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  outcome                STRING,
  customer_ref           STRING,
  client_code            STRING,
  feed_date              DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive TEXTFILE CSV — loaded as CSV');
