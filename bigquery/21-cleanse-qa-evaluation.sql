-- 21-cleanse-qa-evaluation.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_qa_forms
-- writes: ods.ods_qa_evaluation

-- QA scorecards: flatten the sections ARRAY<STRUCT> into per-form totals.
-- Impala nested-collection syntax (f, f.sections s) converted to
-- CROSS JOIN UNNEST(f.sections) AS s per BigQuery standard.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.
-- CAST(... AS DECIMAL(5,2)) → CAST(... AS NUMERIC).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_qa_evaluation WHERE event_date = run_date;

INSERT INTO ods.ods_qa_evaluation
SELECT
  f.qa_form_id,
  f.client_code,
  f.interaction_ref,
  f.evaluator_email,
  TIMESTAMP_MILLIS(f.evaluated_ms)                                        AS evaluated_ts,
  f.form_version,
  CAST(COUNT(s.section_code) AS INT64)                                    AS section_count,
  CAST(SUM(s.scored_points) AS INT64)                                     AS scored_points,
  CAST(SUM(s.max_points) AS INT64)                                        AS max_points,
  f.auto_fail,
  CAST(CASE WHEN f.auto_fail THEN 0
            ELSE ROUND(SUM(s.scored_points) * 100.0 / NULLIF(SUM(s.max_points), 0), 2)
       END AS NUMERIC)                                                    AS overall_pct,
  DATE(TIMESTAMP_MILLIS(f.evaluated_ms))                                  AS event_date
FROM staging.stg_file_qa_forms f
CROSS JOIN UNNEST(f.sections) AS s
WHERE f.feed_date = run_date
GROUP BY f.qa_form_id, f.client_code, f.interaction_ref, f.evaluator_email,
         f.evaluated_ms, f.form_version, f.auto_fail;
