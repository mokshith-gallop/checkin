-- bigquery/ddl/staging/stg_fin_rate_card.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_fin_rate_card (...)
--   PARTITIONED BY (load_date STRING)
--   STORED AS PARQUET
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_fin_rate_card'
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - EXTERNAL, STORED AS PARQUET, LOCATION, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(12,4) → BigQuery NUMERIC(12,4).
--   - Epoch columns (effective_ts, expiry_ts) remain INT64 in staging.
--   - Hive PARTITIONED BY (load_date STRING) → inlined DATE column + PARTITION BY load_date.
--   - Column count: 7 source columns + 1 inlined partition column = 8 total.

CREATE TABLE IF NOT EXISTS staging.stg_fin_rate_card (
  rate_card_id     INT64,
  program_id       INT64,
  service_code     STRING,
  rate             NUMERIC(12,4),
  currency         STRING,
  effective_ts     INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  expiry_ts        INT64 OPTIONS (description = 'epoch SECONDS (legacy)'),
  load_date        DATE
)
PARTITION BY load_date;
