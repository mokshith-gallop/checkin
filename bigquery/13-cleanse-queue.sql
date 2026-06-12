-- 13-cleanse-queue.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_tel_queue
-- writes: ods.ods_queue

-- Cleanse staging.stg_tel_queue -> ods.ods_queue: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: seconds (Telephony source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_queue WHERE snapshot_date = run_date;

INSERT INTO ods.ods_queue
SELECT
  s.queue_id                                                             AS queue_id,
  s.queue_code                                                           AS queue_code,
  s.queue_name                                                           AS queue_name,
  s.program_id                                                           AS program_id,
  s.media_type                                                           AS media_type,
  s.priority                                                             AS priority,
  TIMESTAMP_SECONDS(s.created_epoch)                                     AS created_ts,
  run_date                                                               AS snapshot_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.queue_id ORDER BY s.created_epoch DESC) AS rn
  FROM staging.stg_tel_queue s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
