-- 16-cleanse-call.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_tel_call, staging.stg_tel_call_segment
-- writes: ods.ods_call

-- CDR headers + per-leg segments -> one conformed call row.
-- All telephony epochs are SECONDS (see docs/EPOCH-POLICY.md).
-- Epoch encoding: seconds (Telephony source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_call WHERE call_date = run_date;

INSERT INTO ods.ods_call
SELECT
  c.call_id,
  c.queue_id,
  c.agent_id,
  c.program_id,
  c.direction,
  TIMESTAMP_SECONDS(c.start_epoch)                                  AS start_ts,
  TIMESTAMP_SECONDS(c.answer_epoch)                                 AS answer_ts,
  TIMESTAMP_SECONDS(c.end_epoch)                                    AS end_ts,
  CAST(COALESCE(c.answer_epoch, c.end_epoch) - c.start_epoch AS INT64) AS ring_seconds,
  CAST(COALESCE(seg.talk_secs, 0) AS INT64)                         AS talk_seconds,
  CAST(COALESCE(seg.hold_secs, 0) AS INT64)                         AS hold_seconds,
  CAST(COALESCE(seg.acw_secs,  0) AS INT64)                         AS acw_seconds,
  (c.answer_epoch IS NULL)                                          AS abandoned_flag,
  c.disposition_code,
  c.recording_id,
  DATE(TIMESTAMP_SECONDS(c.start_epoch))                            AS call_date
FROM (
  SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.call_id ORDER BY c.end_epoch DESC) AS rn
  FROM staging.stg_tel_call c
  WHERE c.load_date = run_date
) c
LEFT JOIN (
  SELECT s.call_id,
         SUM(CASE WHEN s.segment_type = 'TALK' THEN s.end_epoch - s.start_epoch END) AS talk_secs,
         SUM(CASE WHEN s.segment_type = 'HOLD' THEN s.end_epoch - s.start_epoch END) AS hold_secs,
         SUM(CASE WHEN s.segment_type = 'ACW'  THEN s.end_epoch - s.start_epoch END) AS acw_secs
  FROM staging.stg_tel_call_segment s
  WHERE s.load_date = run_date
  GROUP BY s.call_id
) seg ON seg.call_id = c.call_id
WHERE c.rn = 1;
