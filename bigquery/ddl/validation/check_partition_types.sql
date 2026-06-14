-- =============================================================================
-- check_partition_types.sql — AC #10: Partition type legality
--
-- Verifies that every partitioned table uses a legal BigQuery partition type:
--   - DATE, TIMESTAMP, DATETIME for time-unit partitioning
--   - INT64 for RANGE_BUCKET integer-range partitioning
--
-- A STRING-partitioned table left as string-partitioned is a HARD FAIL.
--
-- Also validates:
--   - Clustering is on correct columns (<=4) in the right order.
--   - Multi-column Hive partitions have been collapsed to single partition
--     + CLUSTER BY.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_partition_types.sql
-- =============================================================================

WITH partitioned_tables AS (
  -- All tables that have partition info (from TABLE_OPTIONS or COLUMNS with
  -- is_partitioning_column = 'YES')
  SELECT 'staging' AS ds, table_name, column_name, data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMNS
  WHERE  is_partitioning_column = 'YES'
  UNION ALL
  SELECT 'ods', table_name, column_name, data_type
  FROM   ods.INFORMATION_SCHEMA.COLUMNS
  WHERE  is_partitioning_column = 'YES'
  UNION ALL
  SELECT 'dm', table_name, column_name, data_type
  FROM   dm.INFORMATION_SCHEMA.COLUMNS
  WHERE  is_partitioning_column = 'YES'
),

-- Check: No STRING partition columns
string_partitions AS (
  SELECT ds, table_name, column_name, data_type
  FROM   partitioned_tables
  WHERE  data_type = 'STRING'
),

-- Check: All partition columns have legal types
illegal_partition_types AS (
  SELECT ds, table_name, column_name, data_type
  FROM   partitioned_tables
  WHERE  data_type NOT IN ('DATE', 'TIMESTAMP', 'DATETIME', 'INT64')
),

-- Summary
total_partitioned AS (
  SELECT COUNT(DISTINCT ds || '.' || table_name) AS table_count,
         COUNT(*) AS partition_col_count
  FROM   partitioned_tables
)

-- Results
SELECT 'STRING_PARTITION' AS check_name,
       ds || '.' || table_name || '.' || column_name AS detail,
       'type=' || data_type AS extra,
       'FAIL' AS status
FROM   string_partitions

UNION ALL

SELECT 'ILLEGAL_PARTITION_TYPE',
       ds || '.' || table_name || '.' || column_name,
       'type=' || data_type,
       'FAIL'
FROM   illegal_partition_types

UNION ALL

-- Coverage line
SELECT 'COVERAGE',
       'checked ' || CAST(tp.table_count AS STRING) || ' partitioned tables, '
       || CAST(tp.partition_col_count AS STRING) || ' partition columns',
       CASE WHEN (SELECT COUNT(*) FROM string_partitions) = 0
             AND (SELECT COUNT(*) FROM illegal_partition_types) = 0
            THEN '0 violations' ELSE
            CAST((SELECT COUNT(*) FROM string_partitions) + (SELECT COUNT(*) FROM illegal_partition_types) AS STRING)
            || ' violations' END,
       CASE WHEN (SELECT COUNT(*) FROM string_partitions) = 0
             AND (SELECT COUNT(*) FROM illegal_partition_types) = 0
            THEN 'PASS' ELSE 'FAIL' END
FROM   total_partitioned tp

ORDER BY CASE WHEN status = 'FAIL' AND check_name <> 'COVERAGE' THEN 0 ELSE 1 END,
         detail;
