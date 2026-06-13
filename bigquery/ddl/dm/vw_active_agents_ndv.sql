-- bigquery/ddl/dm/vw_active_agents_ndv.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #2
-- Trap: Impala NDV() is an approximate distinct count; the correct BigQuery
--       equivalent is APPROX_COUNT_DISTINCT() (not COUNT(DISTINCT)).
--
-- Conversion notes:
--   - NDV(expr) → APPROX_COUNT_DISTINCT(expr).
--   - Hive CAST(x AS STRING) → BigQuery CAST(x AS STRING) (identical).

CREATE VIEW IF NOT EXISTS dm.vw_active_agents_ndv AS
SELECT f.date_key,
       a.site_code,
       APPROX_COUNT_DISTINCT(f.agent_sk)                                   AS approx_active_agents,
       APPROX_COUNT_DISTINCT(CONCAT(CAST(f.agent_sk AS STRING), '|', f.channel)) AS approx_agent_channel_pairs,
       COUNT(*)                                                            AS interactions
FROM   dm.fact_interaction f
JOIN   dm.dim_agent a ON a.agent_sk = f.agent_sk
GROUP  BY f.date_key, a.site_code;
