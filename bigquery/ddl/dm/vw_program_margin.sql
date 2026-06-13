-- bigquery/ddl/dm/vw_program_margin.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #14
-- Revenue minus labor cost proxy with cross-join wart.
--
-- Conversion notes:
--   - All arithmetic and COALESCE() identical in BigQuery.
--   - The CROSS JOIN wart (ON 1 = 1) is preserved as-is — this is a known
--     legacy pattern where committed minimums are pulled for the margin
--     footnote regardless of program/period.
--   - Subquery aliasing and LEFT JOIN syntax identical.

CREATE VIEW IF NOT EXISTS dm.vw_program_margin AS
SELECT b.period_month,
       b.client_sk,
       b.program_sk,
       b.billed_amount,
       b.net_revenue,
       lab.billable_cost_minutes / 60.0 * 18.50          AS est_labor_cost,   -- blended rate
       adj.total_adjustments,
       b.net_revenue - (lab.billable_cost_minutes / 60.0 * 18.50)
                     - COALESCE(adj.total_adjustments, 0) AS est_margin,
       cmt.committed_min
FROM   dm.agg_billing_monthly b
LEFT   JOIN (
  SELECT t.program_id, t.work_month, SUM(t.billable_minutes) AS billable_cost_minutes
  FROM   ods.ods_timesheet t GROUP BY t.program_id, t.work_month
) lab ON lab.work_month = b.period_month
LEFT   JOIN (
  SELECT p.period_month, SUM(p.amount) AS total_adjustments
  FROM   ods.ods_payroll_adjustment p GROUP BY p.period_month
) adj ON adj.period_month = b.period_month
LEFT   JOIN (
  SELECT cl.contract_id, SUM(cl.min_commit) AS committed_min
  FROM   ods.ods_contract_line cl GROUP BY cl.contract_id
) cmt ON 1 = 1;   -- committed minimums pulled for the margin footnote (legacy cross join wart)
