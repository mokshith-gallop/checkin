-- bigquery/ddl/ods/ods_qa_evaluation.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_qa_evaluation (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2).
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch millis cast in cleanse).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 11 source columns + 1 inlined partition column = 12 total.

CREATE TABLE IF NOT EXISTS ods.ods_qa_evaluation (
  qa_form_id         STRING,
  client_code        STRING,
  interaction_ref    STRING,
  evaluator_email    STRING,
  evaluated_ts       TIMESTAMP,
  form_version       STRING,
  section_count      INT64,
  scored_points      INT64,
  max_points         INT64,
  auto_fail          BOOL,
  overall_pct        NUMERIC(5,2),
  event_date         DATE
)
PARTITION BY event_date;
