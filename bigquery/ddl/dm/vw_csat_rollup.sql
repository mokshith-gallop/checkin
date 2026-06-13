-- bigquery/ddl/dm/vw_csat_rollup.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #3
-- Trap: Hive WITH ROLLUP placement + GROUPING__ID pseudo-column.
--
-- Conversion notes:
--   - Hive GROUP BY col1, col2 WITH ROLLUP →
--     BigQuery GROUP BY ROLLUP(col1, col2).
--   - Hive GROUPING__ID → BigQuery uses GROUPING() function.
--     GROUPING__ID is a bitmask; in BigQuery we reconstruct it using GROUPING()
--     on each column. Hive GROUPING__ID bit order (MSB = leftmost GROUP BY col):
--       0 = both present, 1 = program_code rolled up, 3 = both rolled up.
--     BigQuery GROUPING(col) returns 1 if col is aggregated (rolled up).
--     Reconstructed as: GROUPING(p.client_id) * 2 + GROUPING(p.program_code).

CREATE VIEW IF NOT EXISTS dm.vw_csat_rollup AS
SELECT p.client_id,
       p.program_code,
       COUNT(*)                       AS surveys,
       AVG(s.csat_score)              AS avg_csat,
       SUM(CASE WHEN s.nps_score >= 9 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS pct_promoters,
       GROUPING(p.client_id) * 2 + GROUPING(p.program_code) AS grouping_level
FROM   dm.fact_csat_survey s
JOIN   dm.dim_program p ON p.program_sk = s.program_sk
GROUP  BY ROLLUP(p.client_id, p.program_code);
