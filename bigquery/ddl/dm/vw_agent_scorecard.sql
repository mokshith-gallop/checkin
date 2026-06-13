-- bigquery/ddl/dm/vw_agent_scorecard.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #8
-- Composite ranking: PERCENT_RANK + NTILE over CTEs.
--
-- Conversion notes:
--   - CTE syntax (WITH ... AS), PERCENT_RANK(), NTILE(), COALESCE() are all
--     identical in BigQuery Standard SQL.
--   - Hive BOOLEAN comparison (s.is_current = TRUE, s.certified = TRUE) works
--     in BigQuery as-is.

CREATE VIEW IF NOT EXISTS dm.vw_agent_scorecard AS
WITH perf AS (
  SELECT d.agent_sk,
         AVG(d.avg_handle_seconds)   AS aht,
         AVG(d.adherence_pct)        AS adherence,
         SUM(d.interactions_handled) AS volume
  FROM   dm.agg_agent_daily d
  GROUP  BY d.agent_sk
),
qa AS (
  SELECT q.agent_sk, AVG(q.overall_pct) AS avg_qa_pct
  FROM   dm.fact_qa_evaluation q
  GROUP  BY q.agent_sk
),
skills AS (
  SELECT s.agent_id, COUNT(*) AS certified_skills
  FROM   ods.ods_agent_skill_scd2 s
  WHERE  s.is_current = TRUE AND s.certified = TRUE
  GROUP  BY s.agent_id
)
SELECT a.agent_sk, a.full_name, a.site_code, a.job_grade,
       p.aht, p.adherence, p.volume, q.avg_qa_pct,
       COALESCE(sk.certified_skills, 0) AS certified_skills,
       PERCENT_RANK() OVER (ORDER BY p.aht ASC)          AS aht_pctile,
       NTILE(4)       OVER (ORDER BY q.avg_qa_pct DESC)  AS qa_quartile
FROM   dm.dim_agent a
JOIN   perf p ON p.agent_sk = a.agent_sk
LEFT   JOIN qa q ON q.agent_sk = a.agent_sk
LEFT   JOIN skills sk ON sk.agent_id = a.agent_id
WHERE  a.is_current = TRUE;
