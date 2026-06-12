-- 15-cleanse-adherence-event.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_wfm_adherence_event
-- writes: ods.ods_adherence_event

-- Cleanse staging.stg_wfm_adherence_event -> ods.ods_adherence_event: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: seconds (WFM source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_adherence_event WHERE event_date = run_date;

INSERT INTO ods.ods_adherence_event
SELECT
  s.adherence_event_id                                                   AS adherence_event_id,
  s.agent_id                                                             AS agent_id,
  s.schedule_id                                                          AS schedule_id,
  s.exception_type                                                       AS exception_type,
  TIMESTAMP_SECONDS(s.start_epoch)                                       AS start_ts,
  TIMESTAMP_SECONDS(s.end_epoch)                                         AS end_ts,
  CAST((s.end_epoch - s.start_epoch) / 60 AS INT64)                      AS exception_minutes,
  s.approved_flag                                                        AS approved_flag,
  DATE(TIMESTAMP_SECONDS(s.start_epoch))                                 AS event_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.adherence_event_id ORDER BY s.start_epoch DESC) AS rn
  FROM staging.stg_wfm_adherence_event s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
