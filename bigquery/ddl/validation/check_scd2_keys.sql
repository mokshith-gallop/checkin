-- =============================================================================
-- check_scd2_keys.sql — AC #5: SCD-2 surrogate key validation
--
-- For the 3 SCD-2 tables, verifies:
--   1. Surrogate key columns are STRING type.
--   2. Column descriptions contain 'TO_HEX(MD5(' documenting the
--      BigQuery generation method.
--
-- Usage:
--   bq query --nouse_legacy_sql < check_scd2_keys.sql
-- =============================================================================

WITH scd2_keys AS (
  SELECT 'ods_agent_scd2' AS tbl, 'agent_history_id' AS key_col UNION ALL
  SELECT 'ods_agent_skill_scd2', 'agent_skill_history_id' UNION ALL
  SELECT 'ods_agent_assignment_scd2', 'assignment_history_id'
),

checks AS (
  SELECT s.tbl,
         s.key_col,
         COALESCE(c.data_type, 'MISSING') AS data_type,
         COALESCE(c.description, '') AS col_description,
         -- Check type is STRING
         CASE WHEN c.data_type = 'STRING' THEN 'PASS' ELSE 'FAIL' END AS type_status,
         -- Check description contains TO_HEX(MD5(
         CASE WHEN COALESCE(c.description, '') LIKE '%TO_HEX(MD5(%' THEN 'PASS'
              ELSE 'FAIL' END AS desc_status
  FROM   scd2_keys s
  LEFT   JOIN ods.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS c
         ON c.table_name = s.tbl AND c.column_name = s.key_col
)

SELECT tbl,
       key_col,
       data_type,
       SUBSTR(col_description, 1, 80) AS description_preview,
       type_status AS type_is_string,
       desc_status AS desc_has_md5,
       CASE WHEN type_status = 'PASS' AND desc_status = 'PASS' THEN 'PASS'
            ELSE 'FAIL' END AS overall_status
FROM   checks
ORDER  BY tbl;
