-- bigquery/ddl/ods/ods_contract_line.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_contract_line (...)
--   PARTITIONED BY (snapshot_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive DECIMAL(12,4) → BigQuery NUMERIC(12,4); DECIMAL(12,2) → NUMERIC(12,2).
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (Oracle string dates parsed in cleanse).
--   - Hive PARTITIONED BY (snapshot_date STRING) → inlined DATE column +
--     PARTITION BY snapshot_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_contract_line (
  contract_line_id   INT64,
  contract_id        INT64,
  line_no            INT64,
  service_code       STRING,
  uom                STRING,
  unit_rate          NUMERIC(12,4),
  min_commit         NUMERIC(12,2),
  effective_ts       TIMESTAMP,
  snapshot_date      DATE
)
PARTITION BY snapshot_date;
