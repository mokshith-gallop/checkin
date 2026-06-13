-- bigquery/ddl/dm/vw_queue_sla_attainment.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #10
-- Trap: dm view reads staging.stg_crm_sla_target — a layer-skip that the
--       target architecture must remediate or replicate.
--
-- Conversion notes:
--   - Layer-skip preserved: view references staging.stg_crm_sla_target directly.
--   - NULLIF(), MAX(), SUM(), CASE WHEN syntax identical in BigQuery.
--   - No type or function changes needed.

CREATE VIEW IF NOT EXISTS dm.vw_queue_sla_attainment AS
SELECT q.queue_code,
       q.media_type,
       f.date_key,
       SUM(f.answered_in_sl) / NULLIF(SUM(f.answered), 0) * 100 AS sl_pct,
       MAX(t.target_value)                                       AS sl_target,
       CASE WHEN SUM(f.answered_in_sl) / NULLIF(SUM(f.answered), 0) * 100
                 >= MAX(t.target_value) THEN 'MET' ELSE 'MISSED' END AS attainment
FROM   dm.fact_queue_interval f
JOIN   dm.dim_queue q          ON q.queue_sk = f.queue_sk
LEFT   JOIN staging.stg_crm_sla_target t
       ON t.queue_id = q.queue_id AND t.metric_code = 'SL_20_80'
GROUP  BY q.queue_code, q.media_type, f.date_key;
