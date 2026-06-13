-- bigquery/ddl/dm/vw_first_contact_resolution.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #11
-- Trap: self-join with 7-day window predicate using date_add().
--
-- Conversion notes:
--   - Hive date_add(timestamp, int_days) → BigQuery TIMESTAMP_ADD(ts, INTERVAL n DAY).
--     Hive's date_add with a TIMESTAMP returns a TIMESTAMP + N days;
--     BigQuery's TIMESTAMP_ADD achieves the same.
--   - Self-join logic and GROUP BY are identical.

CREATE VIEW IF NOT EXISTS dm.vw_first_contact_resolution AS
SELECT f.date_key,
       f.program_sk,
       COUNT(*)                                          AS resolved_interactions,
       SUM(CASE WHEN rpt.interaction_id IS NULL THEN 1 ELSE 0 END) AS fcr_count,
       SUM(CASE WHEN rpt.interaction_id IS NULL THEN 1 ELSE 0 END) / COUNT(*) * 100 AS fcr_pct
FROM   dm.fact_interaction f
LEFT   JOIN dm.fact_interaction rpt
       ON  rpt.customer_ref = f.customer_ref
       AND rpt.start_ts > f.end_ts
       AND rpt.start_ts <= TIMESTAMP_ADD(f.end_ts, INTERVAL 7 DAY)
WHERE  f.resolved_flag = TRUE
GROUP  BY f.date_key, f.program_sk;
