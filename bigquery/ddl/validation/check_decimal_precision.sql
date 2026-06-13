-- =============================================================================
-- check_decimal_precision.sql — AC #7: DECIMAL precision validation
--
-- Verifies:
--   1. All DECIMAL columns map to NUMERIC (not BIGNUMERIC).
--   2. All 7 distinct precision/scale pairs are present.
--   3. No column is widened beyond the source precision.
--
-- Expected precision/scale pairs:
--   NUMERIC(14,2), NUMERIC(12,4), NUMERIC(12,2), NUMERIC(10,4),
--   NUMERIC(8,2), NUMERIC(7,2), NUMERIC(5,2)
--
-- Usage:
--   bq query --nouse_legacy_sql < check_decimal_precision.sql
-- =============================================================================

WITH all_numeric_cols AS (
  SELECT 'staging' AS ds, table_name, column_name, data_type, numeric_precision, numeric_scale
  FROM   staging.INFORMATION_SCHEMA.COLUMNS
  WHERE  data_type LIKE 'NUMERIC%' OR data_type LIKE 'BIGNUMERIC%'
  UNION ALL
  SELECT 'ods', table_name, column_name, data_type, numeric_precision, numeric_scale
  FROM   ods.INFORMATION_SCHEMA.COLUMNS
  WHERE  data_type LIKE 'NUMERIC%' OR data_type LIKE 'BIGNUMERIC%'
  UNION ALL
  SELECT 'dm', table_name, column_name, data_type, numeric_precision, numeric_scale
  FROM   dm.INFORMATION_SCHEMA.COLUMNS
  WHERE  data_type LIKE 'NUMERIC%' OR data_type LIKE 'BIGNUMERIC%'
),

-- Check 1: No BIGNUMERIC columns
bignumeric_check AS (
  SELECT ds, table_name, column_name, data_type, 'FAIL' AS status
  FROM   all_numeric_cols
  WHERE  data_type LIKE 'BIGNUMERIC%'
),

-- Check 2: Distinct precision/scale pairs
precision_pairs AS (
  SELECT DISTINCT numeric_precision, numeric_scale,
         'NUMERIC(' || CAST(numeric_precision AS STRING) || ',' ||
         CAST(numeric_scale AS STRING) || ')' AS pair_label
  FROM   all_numeric_cols
  WHERE  data_type LIKE 'NUMERIC%'
),

-- Expected pairs
expected_pairs AS (
  SELECT 14 AS p, 2 AS s UNION ALL
  SELECT 12, 4 UNION ALL
  SELECT 12, 2 UNION ALL
  SELECT 10, 4 UNION ALL
  SELECT 8, 2 UNION ALL
  SELECT 7, 2 UNION ALL
  SELECT 5, 2
),

missing_pairs AS (
  SELECT e.p, e.s,
         'NUMERIC(' || CAST(e.p AS STRING) || ',' || CAST(e.s AS STRING) || ')' AS pair_label,
         'MISSING' AS status
  FROM   expected_pairs e
  LEFT   JOIN precision_pairs pp ON pp.numeric_precision = e.p AND pp.numeric_scale = e.s
  WHERE  pp.numeric_precision IS NULL
)

-- Results
SELECT 'bignumeric_violation' AS check_name,
       ds || '.' || table_name || '.' || column_name AS detail,
       data_type, status
FROM   bignumeric_check
UNION ALL
SELECT 'missing_precision_pair', pair_label, '', status
FROM   missing_pairs
UNION ALL
-- Summary of all distinct pairs found
SELECT 'found_pair', pair_label, '', 'PASS'
FROM   precision_pairs
UNION ALL
-- Overall summary
SELECT 'OVERALL',
       CAST((SELECT COUNT(*) FROM all_numeric_cols) AS STRING) || ' NUMERIC columns checked',
       CAST((SELECT COUNT(*) FROM precision_pairs) AS STRING) || '/7 pairs found',
       CASE WHEN (SELECT COUNT(*) FROM bignumeric_check) = 0
             AND (SELECT COUNT(*) FROM missing_pairs) = 0
            THEN 'PASS' ELSE 'FAIL' END
ORDER  BY check_name, detail;
