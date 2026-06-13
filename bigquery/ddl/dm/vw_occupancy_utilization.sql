-- bigquery/ddl/dm/vw_occupancy_utilization.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #12
-- Pivot of agent-state seconds into handle/ready/aux buckets.
--
-- Conversion notes:
--   - Hive LIKE 'AUX%' → BigQuery LIKE 'AUX%' (identical).
--   - NULLIF(), SUM(), CASE WHEN, IN (...) all identical.
--   - No type or function changes needed.

CREATE VIEW IF NOT EXISTS dm.vw_occupancy_utilization AS
SELECT f.date_key,
       a.site_code,
       f.agent_sk,
       SUM(CASE WHEN f.state_code IN ('TALK','HOLD','ACW') THEN f.state_seconds ELSE 0 END) AS handle_seconds,
       SUM(CASE WHEN f.state_code = 'READY'                THEN f.state_seconds ELSE 0 END) AS ready_seconds,
       SUM(CASE WHEN f.state_code LIKE 'AUX%'              THEN f.state_seconds ELSE 0 END) AS aux_seconds,
       SUM(CASE WHEN f.state_code IN ('TALK','HOLD','ACW') THEN f.state_seconds ELSE 0 END)
         / NULLIF(SUM(CASE WHEN f.state_code IN ('TALK','HOLD','ACW','READY')
                           THEN f.state_seconds ELSE 0 END), 0) * 100 AS occupancy_pct
FROM   dm.fact_agent_activity f
JOIN   dm.dim_agent a ON a.agent_sk = f.agent_sk
GROUP  BY f.date_key, a.site_code, f.agent_sk;
