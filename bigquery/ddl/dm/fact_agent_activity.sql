-- bigquery/ddl/dm/fact_agent_activity.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_agent_activity (...)
--   PARTITIONED BY (date_key INT)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Hive PARTITIONED BY (date_key INT) → inlined INT64 column +
--     PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1)).
--   - Column count: 6 source columns + 1 inlined partition column = 7 total.

CREATE TABLE IF NOT EXISTS dm.fact_agent_activity (
  agent_sk           INT64,
  state_code         STRING,
  state_seconds      INT64,
  occurrence_count   INT64,
  first_state_ts     TIMESTAMP,
  last_state_ts      TIMESTAMP,
  date_key           INT64
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1));
