-- bigquery/ddl/dm/vw_org_hierarchy.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #1
-- Trap: recursive CTE over self-referencing ods_org_unit.
--
-- Conversion notes:
--   - WITH RECURSIVE is supported natively in BigQuery Standard SQL.
--   - Hive CONCAT() → BigQuery CONCAT() (identical syntax).
--   - No type changes needed — all columns are STRING/INT64.

CREATE VIEW IF NOT EXISTS dm.vw_org_hierarchy AS
WITH RECURSIVE org_tree AS (
  SELECT o.org_unit_id, o.unit_code, o.unit_name, o.unit_type,
         o.site_code, o.org_unit_id AS root_unit_id, 0 AS depth,
         o.unit_name AS path_names
  FROM   ods.ods_org_unit o
  WHERE  o.parent_unit_id IS NULL
  UNION ALL
  SELECT c.org_unit_id, c.unit_code, c.unit_name, c.unit_type,
         c.site_code, p.root_unit_id, p.depth + 1,
         CONCAT(p.path_names, ' > ', c.unit_name)
  FROM   ods.ods_org_unit c
  JOIN   org_tree p ON c.parent_unit_id = p.org_unit_id
  WHERE  p.depth < 6
)
SELECT org_unit_id, unit_code, unit_name, unit_type, site_code,
       root_unit_id, depth, path_names
FROM   org_tree;
