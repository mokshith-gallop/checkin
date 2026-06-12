-- 53-load-fact-csat-survey.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_survey_response, dm.fact_interaction, dm.dim_agent
-- writes: dm.fact_csat_survey

-- Surveys join BACK to the interaction fact to inherit its conformed keys
-- (fact-to-fact join — flag for the target model, where csat should join
-- dims directly).
-- from_unixtime(unix_timestamp(ts), 'yyyyMMdd') → CAST(FORMAT_TIMESTAMP('%Y%m%d', ts) AS INT64).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_csat_survey WHERE date_key = date_key_val;

INSERT INTO dm.fact_csat_survey
SELECT
  s.survey_id,
  s.interaction_ref                  AS interaction_id,
  COALESCE(f.client_sk, -1)          AS client_sk,
  COALESCE(f.program_sk, -1)         AS program_sk,
  COALESCE(f.agent_sk, -1)           AS agent_sk,
  s.survey_ts,
  s.csat_score,
  s.nps_score,
  s.fcr_claimed,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', s.survey_ts) AS INT64) AS date_key
FROM ods.ods_survey_response s
LEFT JOIN dm.fact_interaction f ON f.interaction_id = s.interaction_ref
WHERE s.event_date = run_date;
