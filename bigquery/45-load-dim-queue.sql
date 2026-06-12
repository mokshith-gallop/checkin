-- 45-load-dim-queue.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_queue
-- writes: dm.dim_queue

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_queue AS
SELECT q.queue_id AS queue_sk, q.queue_id, q.queue_code, q.queue_name, q.program_id,
       q.media_type, q.priority
FROM ods.ods_queue q
WHERE q.snapshot_date = run_date;
