-- bigquery/ddl/staging/stg_file_telco_invoice.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE EXTERNAL TABLE IF NOT EXISTS staging.stg_file_telco_invoice (...)
--   PARTITIONED BY (client_code STRING, feed_date STRING)
--   STORED AS SEQUENCEFILE
--   LOCATION 'hdfs://nbcs-cdh-ns/data/staging/stg_file_telco_invoice';
--
-- Conversion notes:
--   - EXTERNAL, STORED AS SEQUENCEFILE, LOCATION dropped (BigQuery managed table).
--   - Source data is converted from SequenceFile to Parquet/JSON before BQ load.
--   - Hive BIGINT → BigQuery INT64.
--   - Hive STRING  → BigQuery STRING.
--   - Hive DECIMAL(12,2) → BigQuery NUMERIC(12,2).
--   - Epoch column (billed_ms) remains INT64 in staging (epoch MILLISECONDS).
--   - Hive multi-column partition (client_code, feed_date): feed_date inlined as DATE +
--     PARTITION BY feed_date; client_code demoted to regular column + CLUSTER BY.
--   - Column count: 7 source columns + 2 inlined partition columns = 9 total.

CREATE TABLE IF NOT EXISTS staging.stg_file_telco_invoice (
  telco_invoice_id   STRING,
  carrier            STRING,
  circuit_id         STRING,
  usage_minutes      INT64,
  charge_amount      NUMERIC(12,2),
  bill_period        STRING,
  billed_ms          INT64 OPTIONS (description = 'epoch MILLISECONDS (legacy)'),
  client_code        STRING,
  feed_date          DATE
)
PARTITION BY feed_date
CLUSTER BY client_code
OPTIONS (description = 'Source: Hive SequenceFile — converted to Parquet/JSON for BQ load');
