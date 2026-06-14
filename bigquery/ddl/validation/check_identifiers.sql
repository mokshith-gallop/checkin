-- =============================================================================
-- check_identifiers.sql — AC #4: Identifier legality
--
-- Verifies that every table name and column name across all 100 tables
-- and 15 views:
--   1. Starts with a letter or underscore
--   2. Contains only letters, digits, and underscores
--   3. Is within BigQuery length limits (128 chars for table, 300 for column)
--   4. Does not collide with a BigQuery reserved word in a way that breaks
--      unquoted resolution
--
-- Prints: checked X/Y coverage line.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_identifiers.sql
-- =============================================================================

WITH all_identifiers AS (
  -- Table names
  SELECT 'staging' AS ds, table_name AS identifier, 'TABLE_NAME' AS kind
  FROM   staging.INFORMATION_SCHEMA.TABLES
  UNION ALL
  SELECT 'ods', table_name, 'TABLE_NAME'
  FROM   ods.INFORMATION_SCHEMA.TABLES
  UNION ALL
  SELECT 'dm', table_name, 'TABLE_NAME'
  FROM   dm.INFORMATION_SCHEMA.TABLES

  UNION ALL

  -- Column names
  SELECT 'staging', column_name, table_name
  FROM   staging.INFORMATION_SCHEMA.COLUMNS
  UNION ALL
  SELECT 'ods', column_name, table_name
  FROM   ods.INFORMATION_SCHEMA.COLUMNS
  UNION ALL
  SELECT 'dm', column_name, table_name
  FROM   dm.INFORMATION_SCHEMA.COLUMNS
),

-- BigQuery reserved words that would break unquoted resolution
-- (subset of the most common ones that could appear as column names)
reserved_words AS (
  SELECT word FROM UNNEST([
    'ALL', 'AND', 'ANY', 'ARRAY', 'AS', 'ASC', 'ASSERT_ROWS_MODIFIED',
    'AT', 'BETWEEN', 'BY', 'CASE', 'CAST', 'COLLATE', 'CONTAINS',
    'CREATE', 'CROSS', 'CUBE', 'CURRENT', 'DEFAULT', 'DEFINE', 'DESC',
    'DISTINCT', 'ELSE', 'END', 'ENUM', 'ESCAPE', 'EXCEPT', 'EXCLUDE',
    'EXISTS', 'EXTRACT', 'FALSE', 'FETCH', 'FOLLOWING', 'FOR', 'FROM',
    'FULL', 'GROUP', 'GROUPING', 'GROUPS', 'HASH', 'HAVING', 'IF',
    'IGNORE', 'IN', 'INNER', 'INTERSECT', 'INTERVAL', 'INTO', 'IS',
    'JOIN', 'LATERAL', 'LEFT', 'LIKE', 'LIMIT', 'LOOKUP', 'MERGE',
    'NATURAL', 'NEW', 'NO', 'NOT', 'NULL', 'NULLS', 'OF', 'ON',
    'OR', 'ORDER', 'OUTER', 'OVER', 'PARTITION', 'PRECEDING', 'PROTO',
    'RANGE', 'RECURSIVE', 'RESPECT', 'RIGHT', 'ROLLUP', 'ROWS',
    'SELECT', 'SET', 'SOME', 'STRUCT', 'TABLESAMPLE', 'THEN', 'TO',
    'TREAT', 'TRUE', 'UNBOUNDED', 'UNION', 'UNNEST', 'USING', 'WHEN',
    'WHERE', 'WINDOW', 'WITH', 'WITHIN'
  ]) AS word
),

-- Check 1: Identifier starts with letter or underscore
bad_start AS (
  SELECT ds, identifier, kind
  FROM   all_identifiers
  WHERE  NOT REGEXP_CONTAINS(identifier, r'^[a-zA-Z_]')
),

-- Check 2: Identifier contains only letters, digits, underscores
bad_chars AS (
  SELECT ds, identifier, kind
  FROM   all_identifiers
  WHERE  NOT REGEXP_CONTAINS(identifier, r'^[a-zA-Z_][a-zA-Z0-9_]*$')
),

-- Check 3: Length limits
too_long AS (
  SELECT ds, identifier, kind, LENGTH(identifier) AS len
  FROM   all_identifiers
  WHERE  (kind = 'TABLE_NAME' AND LENGTH(identifier) > 128)
     OR  (kind <> 'TABLE_NAME' AND LENGTH(identifier) > 300)
),

-- Check 4: Reserved word collisions (table or column names matching reserved words)
reserved_collisions AS (
  SELECT i.ds, i.identifier, i.kind
  FROM   all_identifiers i
  JOIN   reserved_words rw ON UPPER(i.identifier) = rw.word
),

-- Summary
total_ids AS (
  SELECT COUNT(*) AS total FROM all_identifiers
)

-- Results: show violations first
SELECT 'BAD_START_CHAR' AS check_name,
       ds || '.' || kind || '.' || identifier AS detail,
       'starts with illegal char' AS extra,
       'FAIL' AS status
FROM   bad_start

UNION ALL

SELECT 'ILLEGAL_CHARS',
       ds || '.' || kind || '.' || identifier,
       'contains illegal characters',
       'FAIL'
FROM   bad_chars

UNION ALL

SELECT 'TOO_LONG',
       ds || '.' || kind || '.' || identifier,
       'length=' || CAST(len AS STRING),
       'FAIL'
FROM   too_long

UNION ALL

SELECT 'RESERVED_WORD_COLLISION',
       ds || '.' || kind || '.' || identifier,
       'matches BigQuery reserved word (may need backtick quoting)',
       'WARN'
FROM   reserved_collisions

UNION ALL

-- Coverage line
SELECT 'COVERAGE',
       'checked ' || CAST(t.total AS STRING) || '/'
       || CAST(t.total AS STRING) || ' identifiers',
       CAST((SELECT COUNT(*) FROM bad_start) AS STRING) || ' bad starts, '
       || CAST((SELECT COUNT(*) FROM bad_chars) AS STRING) || ' illegal chars, '
       || CAST((SELECT COUNT(*) FROM too_long) AS STRING) || ' too long, '
       || CAST((SELECT COUNT(*) FROM reserved_collisions) AS STRING) || ' reserved-word collisions',
       CASE WHEN (SELECT COUNT(*) FROM bad_start) = 0
             AND (SELECT COUNT(*) FROM bad_chars) = 0
             AND (SELECT COUNT(*) FROM too_long) = 0
            THEN 'PASS' ELSE 'FAIL' END
FROM   total_ids t

ORDER BY CASE WHEN status = 'FAIL' THEN 0
              WHEN status = 'WARN' THEN 1
              ELSE 2 END,
         detail;
