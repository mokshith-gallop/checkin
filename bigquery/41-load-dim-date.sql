-- 41-load-dim-date.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  GCS staged parquet (replaces HDFS LOAD DATA INPATH)
-- writes: dm.dim_date

-- dim_date is built offline (datagen) and loaded from staged parquet.
-- Legacy Impala used LOAD DATA INPATH from HDFS; BigQuery has no equivalent.
-- Replacement: bq load from GCS, or CREATE OR REPLACE from an external table.

-- Option A (preferred): bq CLI load from GCS — run before this script:
--   bq load --source_format=PARQUET --replace dm.dim_date gs://nbcs-data/incoming/dim_date/*.parquet

-- Option B: external table approach (inline SQL):
CREATE OR REPLACE TABLE dm.dim_date AS
SELECT *
FROM EXTERNAL_QUERY(
  -- Replace with actual GCS external table or connection reference.
  -- Example using BigQuery external table over GCS parquet:
  -- dm.dim_date_external
  -- The actual external table must be pre-created pointing to
  -- gs://nbcs-data/incoming/dim_date/*.parquet
  dm.dim_date_staging
);

-- Note: The operational runbook must define which loading mechanism is used.
-- Both options produce an identical dm.dim_date table from the source parquet.
-- REFRESH / COMPUTE STATS removed — not applicable in BigQuery.
