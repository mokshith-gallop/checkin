-- bigquery/ddl/dm/vw_client_executive_summary.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #15
-- The HUB view — wide multi-fact join consumed by monthly client decks.
-- Guarantees dm-layer connectivity.
--
-- Conversion notes:
--   - All JOIN syntax, subqueries, CASE WHEN, SUM() identical in BigQuery.
--   - No type or function changes needed.

CREATE VIEW IF NOT EXISTS dm.vw_client_executive_summary AS
SELECT c.client_code,
       c.client_name,
       pm.period_month,
       pr.program_code,
       pm.interactions,
       pm.avg_handle_seconds,
       pm.avg_csat,
       cs.pct_promoters,
       cs.pct_detractors,
       bm.billed_amount,
       bm.sla_credit_amount,
       bm.net_revenue,
       tk.open_tickets,
       tk.sla_breached_tickets
FROM   dm.dim_client c
JOIN   dm.dim_program pr            ON pr.client_id = c.client_id
JOIN   dm.agg_program_monthly pm    ON pm.program_sk = pr.program_sk AND pm.grouping_level = 0
LEFT   JOIN dm.agg_csat_rollup_monthly cs
       ON cs.program_sk = pr.program_sk AND cs.period_month = pm.period_month
LEFT   JOIN dm.agg_billing_monthly bm
       ON bm.program_sk = pr.program_sk AND bm.period_month = pm.period_month
LEFT   JOIN (
  SELECT t.program_sk,
         SUM(CASE WHEN t.status IN ('OPEN','PENDING') THEN 1 ELSE 0 END) AS open_tickets,
         SUM(CASE WHEN t.sla_breached_flag THEN 1 ELSE 0 END)            AS sla_breached_tickets
  FROM   dm.fact_ticket t GROUP BY t.program_sk
) tk ON tk.program_sk = pr.program_sk;
