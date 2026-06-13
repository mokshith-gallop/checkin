-- bigquery/ddl/staging/stg_file_qa_forms.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_qa_forms (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_qa_forms'
--   TBLPROPERTIES ('ignore.malformed.json'='true');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT SERDE, STORED AS TEXTFILE, LOCATION, TBLPROPERTIES dropped
--     (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2).
--   - Hive ARRAY<STRUCT<section_code:STRING,max_points:INT,scored_points:INT>> →
--     BigQuery ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>.
--     INT sub-fields widened to INT64 per BigQuery type system.
--   - Epoch column (evaluated_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 8 source columns + 2 inlined partition columns = 10 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_qa_forms (
  qa_form_id       STRING,
  interaction_ref  STRING,
  evaluator_email  STRING,
  evaluated_ms     INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  form_version     STRING,
  sections         ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>,
  auto_fail        BOOL,
  overall_pct      NUMERIC(5,2),
  client_code      STRING,
  feed_date        DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive JsonSerDe — loaded as NEWLINE_DELIMITED_JSON');
