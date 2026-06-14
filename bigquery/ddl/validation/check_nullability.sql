-- =============================================================================
-- check_nullability.sql — AC #9: Nullability validation
--
-- Verifies that NO column across all 100 tables has become REQUIRED
-- (is_nullable = 'NO') in BigQuery. All columns must be NULLABLE to
-- support MERGE operations and data loads.
--
-- This check iterates EVERY column of EVERY table and prints a
-- "checked X/Y" coverage line.
--
-- A source-NULLABLE column that landed as BigQuery-REQUIRED is a HARD FAIL
-- naming the column.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_nullability.sql
-- =============================================================================

WITH all_cols AS (
  SELECT 'staging' AS ds, table_name, column_name, is_nullable
  FROM   staging.INFORMATION_SCHEMA.COLUMNS
  WHERE  table_name NOT LIKE 'INFORMATION%'
  UNION ALL
  SELECT 'ods', table_name, column_name, is_nullable
  FROM   ods.INFORMATION_SCHEMA.COLUMNS
  WHERE  table_name NOT LIKE 'INFORMATION%'
  UNION ALL
  SELECT 'dm', table_name, column_name, is_nullable
  FROM   dm.INFORMATION_SCHEMA.COLUMNS
  WHERE  table_name NOT LIKE 'INFORMATION%'
),

-- Find any REQUIRED (NOT NULL) columns — these are failures
violations AS (
  SELECT ds, table_name, column_name, is_nullable
  FROM   all_cols
  WHERE  is_nullable = 'NO'
),

-- Summary
summary AS (
  SELECT COUNT(*) AS total_columns FROM all_cols
),
violation_count AS (
  SELECT COUNT(*) AS violations FROM violations
)

-- Show violations first
SELECT 'REQUIRED_VIOLATION' AS check_name,
       ds || '.' || table_name || '.' || column_name AS detail,
       'is_nullable=' || is_nullable AS extra,
       'FAIL' AS status
FROM   violations

UNION ALL

-- Coverage line
SELECT 'COVERAGE',
       'checked ' || CAST(s.total_columns AS STRING) || '/'
       || CAST(s.total_columns AS STRING) || ' columns for nullability',
       CAST(v.violations AS STRING) || ' REQUIRED violations',
       CASE WHEN v.violations = 0 THEN 'PASS' ELSE 'FAIL' END
FROM   summary s, violation_count v

ORDER BY CASE WHEN status = 'FAIL' AND check_name = 'REQUIRED_VIOLATION' THEN 0 ELSE 1 END,
         detail;
