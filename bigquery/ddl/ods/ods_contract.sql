-- bigquery/ddl/ods/ods_contract.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_contract (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (Oracle string dates parsed in cleanse).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date.
--   - Column count: 10 source columns + 1 inlined partition column = 11 total.

CREATE TABLE IF NOT EXISTS ods.ods_contract (
  contract_id      INT64,
  client_id        INT64,
  program_id       INT64,
  contract_no      STRING,
  start_ts         TIMESTAMP,
  end_ts           TIMESTAMP,
  billing_model    STRING,
  currency         STRING,
  signed_ts        TIMESTAMP,
  status           STRING,
  snapshot_date    DATE
)
PARTITION BY snapshot_date;
