-- bigquery/ddl/dm/fact_interaction.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS dm.fact_interaction (...)
--   PARTITIONED BY (date_key INT, channel STRING)
--   CLUSTERED BY (agent_sk) INTO 16 BUCKETS
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP.
--   - Hive multi-column partition (date_key INT, channel STRING): BigQuery supports
--     only a single partition column. date_key partitioned via RANGE_BUCKET;
--     channel demoted to a regular STRING column and used as first CLUSTER BY key.
--   - Hive CLUSTERED BY (agent_sk) INTO 16 BUCKETS → included in CLUSTER BY keys.
--   - CLUSTER BY channel, agent_sk, client_sk (max 4 keys; most-queried columns).
--   - Column count: 11 source columns + 2 inlined partition columns = 13 total.

CREATE TABLE IF NOT EXISTS dm.fact_interaction (
  interaction_id     STRING,
  client_sk          INT64,
  program_sk         INT64,
  queue_sk           INT64,
  agent_sk           INT64,
  customer_ref       STRING,
  start_ts           TIMESTAMP,
  end_ts             TIMESTAMP,
  handle_seconds     INT64,
  resolved_flag      BOOL,
  source_system      STRING,
  date_key           INT64,
  channel            STRING
)
PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000))
CLUSTER BY channel, agent_sk, client_sk;
