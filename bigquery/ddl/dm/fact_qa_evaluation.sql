-- bigquery/ddl/dm/fact_qa_evaluation.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_qa_evaluation (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(5,2) → BigQuery NUMERIC(5,2).
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1)).
--   - Column count: 9 source columns + 1 inlined partition column = 10 total.

CREATE TABLE IF NOT EXISTS dm.fact_qa_evaluation (
  qa_form_id         STRING,
  interaction_id     STRING,
  agent_sk           INT64,
  program_sk         INT64,
  evaluated_ts       TIMESTAMP,
  scored_points      INT64,
  max_points         INT64,
  overall_pct        NUMERIC(5,2),
  auto_fail          BOOL,
  date_key           INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1));
