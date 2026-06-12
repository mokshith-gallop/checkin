-- 12-cleanse-org-unit.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_hr_org_unit
-- writes: ods.ods_org_unit

-- Cleanse staging.stg_hr_org_unit -> ods.ods_org_unit: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: seconds (HR source) → TIMESTAMP_SECONDS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_org_unit WHERE snapshot_date = run_date;

INSERT INTO ods.ods_org_unit
SELECT
  s.org_unit_id                                                          AS org_unit_id,
  s.parent_unit_id                                                       AS parent_unit_id,
  s.unit_code                                                            AS unit_code,
  s.unit_name                                                            AS unit_name,
  s.unit_type                                                            AS unit_type,
  s.site_code                                                            AS site_code,
  s.cost_center                                                          AS cost_center,
  TIMESTAMP_SECONDS(s.created_ts)                                        AS created_ts,
  run_date                                                               AS snapshot_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.org_unit_id ORDER BY s.created_ts DESC) AS rn
  FROM staging.stg_hr_org_unit s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
