-- bigquery/ddl/staging/stg_file_speech_analytics.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_speech_analytics (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_speech_analytics'
--   TBLPROPERTIES ('ignore.malformed.json'='true');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT SERDE (JsonSerDe), STORED AS TEXTFILE, LOCATION, TBLPROPERTIES
--     dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DOUBLE → BigQuery FLOAT64.
--   - Hive ARRAY<STRING> → BigQuery ARRAY<STRING> (REPEATED STRING).
--   - Epoch column (analyzed_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_speech_analytics (
  recording_id       STRING,
  call_ref           STRING,
  analyzed_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  sentiment_score    FLOAT64,
  silence_pct        FLOAT64,
  talk_over_count    INT64,
  keywords           ARRAY<STRING>,
  client_code        STRING,
  feed_date          DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive JsonSerDe — loaded as NEWLINE_DELIMITED_JSON');
