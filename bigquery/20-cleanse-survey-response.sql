-- 20-cleanse-survey-response.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_survey_csat
-- writes: ods.ods_survey_response

-- Cleanse staging.stg_file_survey_csat -> ods.ods_survey_response: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_survey_response WHERE event_date = run_date;

INSERT INTO ods.ods_survey_response
SELECT
  s.survey_id                                                            AS survey_id,
  s.client_code                                                          AS client_code,
  s.interaction_ref                                                      AS interaction_ref,
  TIMESTAMP_MILLIS(s.survey_ms)                                          AS survey_ts,
  s.csat_score                                                           AS csat_score,
  s.nps_score                                                            AS nps_score,
  s.fcr_claimed                                                          AS fcr_claimed,
  TRIM(s.verbatim)                                                       AS verbatim,
  DATE(TIMESTAMP_MILLIS(s.survey_ms))                                    AS event_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.survey_id ORDER BY s.survey_ms DESC) AS rn
  FROM staging.stg_file_survey_csat s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
