-- bigquery/ddl/staging/stg_file_ivr_logs.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_ivr_logs (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
--   WITH SERDEPROPERTIES ('input.regex' = '^(\\d+)\\|([A-Z0-9-]+)\\|MENU:([^;]*);KEY:([0-9*#])\\|(.*)$')
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_ivr_logs';
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT SERDE (RegexSerDe), WITH SERDEPROPERTIES, STORED AS TEXTFILE,
--     LOCATION dropped (BigQuery managed table).
--   - Source data is pre-processed (regex-parsed) to structured format before BQ load.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch column (event_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 5 source columns + 2 inlined partition columns = 7 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_ivr_logs (
  event_ms       INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  session_ref    STRING,
  menu_path      STRING,
  key_pressed    STRING,
  raw_tail       STRING,
  client_code    STRING,
  feed_date      DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive RegexSerDe — pre-processed to structured format before BQ load');
