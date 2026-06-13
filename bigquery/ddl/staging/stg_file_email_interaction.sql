-- bigquery/ddl/staging/stg_file_email_interaction.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_email_interaction (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
--   LINES TERMINATED BY '\n'
--   STORED AS TEXTFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_email_interaction'
--   TBLPROPERTIES ('skip.header.line.count'='1');
--
-- Conversion notes:
--   - EXTERNAL, ROW FORMAT, STORED AS TEXTFILE, LOCATION, TBLPROPERTIES dropped
--     (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Epoch columns (received_ms, first_reply_ms, resolved_ms) remain INT64 in staging
--     (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_email_interaction (
  email_ref          STRING,
  mailbox            STRING,
  agent_email        STRING,
  received_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  first_reply_ms     INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  resolved_ms        INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  subject_category   STRING,
  client_code        STRING,
  feed_date          DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive TEXTFILE CSV — loaded as CSV');
