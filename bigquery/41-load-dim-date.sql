-- 41-load-dim-date.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  GCS staged parquet (replaces HDFS LOAD DATA INPATH)
-- writes: dm.dim_date

-- dim_date is built offline (datagen) and loaded from staged parquet.
-- Legacy Impala used LOAD DATA INPATH from HDFS; BigQuery has no equivalent.
-- Replacement options (choose one during deployment):
--
-- Option A (preferred): bq CLI load from GCS — run this shell command:
--   bq load --source_format=PARQUET --replace dm.dim_date \
--       gs://nbcs-data/incoming/dim_date/*.parquet
--
-- Option B: SQL via a pre-created external table pointing at GCS parquet.
--   The external table dm.dim_date_ext must be created once via:
--     CREATE EXTERNAL TABLE dm.dim_date_ext
--     WITH PARTITION COLUMNS
--     OPTIONS (
--       format = 'PARQUET',
--       uris = ['gs://nbcs-data/incoming/dim_date/*.parquet']
--     );

CREATE OR REPLACE TABLE dm.dim_date AS
SELECT *
FROM dm.dim_date_ext;

-- Note: The operational runbook must define which loading mechanism is used.
-- Both options produce an identical dm.dim_date table from the source parquet.
-- REFRESH / COMPUTE STATS removed — not applicable in BigQuery.
