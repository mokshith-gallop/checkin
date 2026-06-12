-- 48-load-dim-org.sql  [dim]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_org_unit
-- writes: dm.dim_org

-- Flatten the org tree to 4 fixed levels via self-joins (the recursive-CTE
-- view exists for analysts; ETL flattens the hard way).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

CREATE OR REPLACE TABLE dm.dim_org AS
SELECT
  l4.org_unit_id                    AS org_sk,
  l4.org_unit_id,
  l4.unit_code,
  l4.unit_name,
  l4.unit_type,
  COALESCE(l1.unit_name, l4.unit_name) AS level1_name,
  COALESCE(l2.unit_name, l4.unit_name) AS level2_name,
  COALESCE(l3.unit_name, l4.unit_name) AS level3_name,
  l4.unit_name                          AS level4_name,
  COALESCE(l4.site_code, l3.site_code, l2.site_code) AS site_code,
  l4.cost_center
FROM ods.ods_org_unit l4
LEFT JOIN ods.ods_org_unit l3 ON l3.org_unit_id = l4.parent_unit_id
                             AND l3.snapshot_date = l4.snapshot_date
LEFT JOIN ods.ods_org_unit l2 ON l2.org_unit_id = l3.parent_unit_id
                             AND l2.snapshot_date = l4.snapshot_date
LEFT JOIN ods.ods_org_unit l1 ON l1.org_unit_id = l2.parent_unit_id
                             AND l1.snapshot_date = l4.snapshot_date
WHERE l4.snapshot_date = run_date;
