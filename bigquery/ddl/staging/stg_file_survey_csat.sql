-- bigquery/ddl/staging/stg_file_survey_csat.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_survey_csat (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_survey_csat'
--   TBLPROPERTIES ('skip.header.line.count'='1');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION, TBLPROPERTIES dropped
--     (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Epoch column (survey_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_survey_csat (
  survey_id        STRING,
  interaction_ref  STRING,
  survey_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  csat_score       INT64,
  nps_score        INT64,
  fcr_claimed      BOOL,
  verbatim         STRING,
  client_code      STRING,
  feed_date        DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive TEXTFILE CSV — loaded as CSV');
