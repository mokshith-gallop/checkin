-- 14-cleanse-schedule.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_wfm_schedule, staging.stg_wfm_shift
-- writes: ods.ods_schedule

-- Cleanse staging.stg_wfm_schedule -> ods.ods_schedule: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: seconds (WFM source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_schedule WHERE sched_date = run_date;

INSERT INTO ods.ods_schedule
SELECT
  s.schedule_id                                                          AS schedule_id,
  s.agent_id                                                             AS agent_id,
  s.shift_id                                                             AS shift_id,
  sh.shift_code                                                          AS shift_code,
  TIMESTAMP_SECONDS(s.start_epoch)                                       AS start_ts,
  TIMESTAMP_SECONDS(s.end_epoch)                                         AS end_ts,
  s.paid_minutes                                                         AS paid_minutes,
  s.activity_code                                                        AS activity_code,
  s.site_code                                                            AS site_code,
  s.sched_date                                                           AS sched_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.schedule_id ORDER BY s.start_epoch DESC) AS rn
  FROM staging.stg_wfm_schedule s
  WHERE s.load_date = run_date
) s JOIN staging.stg_wfm_shift sh ON sh.shift_id = s.shift_id
WHERE s.rn = 1;
