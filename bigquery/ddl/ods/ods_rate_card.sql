-- bigquery/ddl/ods/ods_rate_card.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_rate_card (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive DECIMAL(12,4) → BigQuery NUMERIC(12,4).
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds and delta cast in merge).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_rate_card (
  rate_card_id     INT64,
  program_id       INT64,
  service_code     STRING,
  rate             NUMERIC(12,4),
  currency         STRING,
  effective_ts     TIMESTAMP,
  expiry_ts        TIMESTAMP,
  last_change_ts   TIMESTAMP,
  snapshot_date    DATE
)
PARTITION BY snapshot_date;
