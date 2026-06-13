-- bigquery/ddl/dm/vw_attrition_risk.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #9
-- Nested CTEs + NTILE banding for attrition risk scoring.
--
-- Conversion notes:
--   - Nested CTEs, NTILE(), COALESCE(), CASE WHEN are all identical in
--     BigQuery Standard SQL.
--   - No type or function changes needed.

CREATE VIEW IF NOT EXISTS dm.vw_attrition_risk AS
WITH adh AS (
  SELECT f.agent_sk, AVG(f.adherence_pct) AS adherence_90d
  FROM   dm.fact_adherence_daily f
  GROUP  BY f.agent_sk
),
notice AS (
  SELECT e.agent_id, COUNT(*) AS notice_events
  FROM   ods.ods_attrition_event e
  GROUP  BY e.agent_id
),
wk AS (
  SELECT w.agent_sk, AVG(w.interactions_handled) AS weekly_volume
  FROM   dm.agg_agent_weekly w
  GROUP  BY w.agent_sk
),
banded AS (
  SELECT a.agent_sk, a.agent_id, a.full_name, a.site_code,
         adh.adherence_90d,
         COALESCE(n.notice_events, 0) AS notice_events,
         NTILE(5) OVER (ORDER BY adh.adherence_90d ASC) AS adherence_band
  FROM   dm.dim_agent a
  JOIN   adh    ON adh.agent_sk = a.agent_sk
  LEFT   JOIN notice n ON n.agent_id = a.agent_id
  LEFT   JOIN wk ON wk.agent_sk = a.agent_sk
  WHERE  a.is_current = TRUE AND a.status = 'ACTIVE'
)
SELECT agent_sk, agent_id, full_name, site_code, adherence_90d, notice_events,
       CASE WHEN adherence_band = 1 OR notice_events > 0 THEN 'HIGH'
            WHEN adherence_band = 2 THEN 'MEDIUM' ELSE 'LOW' END AS attrition_risk
FROM   banded;
