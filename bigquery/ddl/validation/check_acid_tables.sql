-- =============================================================================
-- check_acid_tables.sql — AC #4: ACID table validation
--
-- For the 4 ACID tables (ods_client_acid, ods_agent_acid, ods_ticket_acid,
-- ods_invoice_acid), verifies:
--   1. Each exists as BASE TABLE (not EXTERNAL).
--   2. All columns are nullable (is_nullable = 'YES') for MERGE compatibility.
--   3. No table or column description contains 'ORC' or 'transactional'.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_acid_tables.sql
-- =============================================================================

WITH acid_tables AS (
  SELECT 'ods_client_acid' AS tbl UNION ALL
  SELECT 'ods_agent_acid' UNION ALL
  SELECT 'ods_ticket_acid' UNION ALL
  SELECT 'ods_invoice_acid'
),

-- Check 1: Table type is BASE TABLE
table_type_check AS (
  SELECT a.tbl,
         COALESCE(t.table_type, 'MISSING') AS table_type,
         CASE WHEN t.table_type = 'BASE TABLE' THEN 'PASS'
              WHEN t.table_type IS NULL THEN 'MISSING'
              ELSE 'FAIL' END AS status
  FROM   acid_tables a
  LEFT   JOIN ods.INFORMATION_SCHEMA.TABLES t ON t.table_name = a.tbl
),

-- Check 2: All columns nullable (no NOT NULL)
nullable_check AS (
  SELECT c.table_name AS tbl,
         c.column_name,
         c.is_nullable,
         CASE WHEN c.is_nullable = 'YES' THEN 'PASS' ELSE 'FAIL' END AS status
  FROM   ods.INFORMATION_SCHEMA.COLUMNS c
  WHERE  c.table_name IN ('ods_client_acid', 'ods_agent_acid',
                           'ods_ticket_acid', 'ods_invoice_acid')
    AND  c.is_nullable <> 'YES'
),

-- Check 3: No column description references ORC or transactional
desc_check AS (
  SELECT c.table_name AS tbl,
         c.column_name,
         COALESCE(c.description, '') AS col_description,
         'FAIL' AS status
  FROM   ods.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS c
  WHERE  c.table_name IN ('ods_client_acid', 'ods_agent_acid',
                           'ods_ticket_acid', 'ods_invoice_acid')
    AND  (UPPER(COALESCE(c.description, '')) LIKE '%ORC%'
      OR  UPPER(COALESCE(c.description, '')) LIKE '%TRANSACTIONAL%')
)

-- Results
SELECT 'table_type' AS check_category, tbl, '' AS column_name, table_type AS detail, status
FROM   table_type_check
UNION ALL
SELECT 'not_null_violation', tbl, column_name, 'is_nullable=' || is_nullable, status
FROM   nullable_check
UNION ALL
SELECT 'bad_description', tbl, column_name, col_description, status
FROM   desc_check
UNION ALL
-- Summary
SELECT 'SUMMARY',
       CAST((SELECT COUNT(*) FROM table_type_check WHERE status = 'PASS') AS STRING) || '/4 tables exist as BASE TABLE',
       CAST((SELECT COUNT(*) FROM nullable_check) AS STRING) || ' NOT NULL violations',
       '',
       CASE WHEN (SELECT COUNT(*) FROM table_type_check WHERE status <> 'PASS') = 0
             AND (SELECT COUNT(*) FROM nullable_check) = 0
             AND (SELECT COUNT(*) FROM desc_check) = 0
            THEN 'PASS' ELSE 'FAIL' END
ORDER BY check_category;
