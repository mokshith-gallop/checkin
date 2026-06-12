-- 54-load-fact-qa-evaluation.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_qa_evaluation, dm.fact_interaction, dm.dim_agent
-- writes: dm.fact_qa_evaluation

-- from_unixtime(unix_timestamp(ts), 'yyyyMMdd') → CAST(FORMAT_TIMESTAMP('%Y%m%d', ts) AS INT64).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_qa_evaluation WHERE date_key = date_key_val;

INSERT INTO dm.fact_qa_evaluation
SELECT
  q.qa_form_id,
  q.interaction_ref                  AS interaction_id,
  COALESCE(f.agent_sk, -1)           AS agent_sk,
  COALESCE(f.program_sk, -1)         AS program_sk,
  q.evaluated_ts,
  q.scored_points,
  q.max_points,
  q.overall_pct,
  q.auto_fail,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', q.evaluated_ts) AS INT64) AS date_key
FROM ods.ods_qa_evaluation q
LEFT JOIN dm.fact_interaction f ON f.interaction_id = q.interaction_ref
WHERE q.event_date = run_date;
