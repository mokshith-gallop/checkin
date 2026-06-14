-- =============================================================================
-- check_complex_types.sql — AC #8: Complex type validation
--
-- Verifies ARRAY<STRUCT>, ARRAY<STRING>, and JSON columns via
-- INFORMATION_SCHEMA.COLUMN_FIELD_PATHS with RECURSIVE sub-field checks.
--
-- Expected:
--   stg_file_qa_forms.sections       → ARRAY<STRUCT<section_code STRING,
--                                        max_points INT64, scored_points INT64>>
--   stg_file_chat_transcripts.messages → ARRAY<STRUCT<sender STRING,
--                                          ts_ms INT64, text STRING>>
--   stg_file_chat_transcripts.metadata → JSON
--   stg_file_speech_analytics.keywords → ARRAY<STRING> (REPEATED STRING)
--
-- Usage:
--   bq query --nouse_legacy_sql < check_complex_types.sql
-- =============================================================================

WITH checks AS (
  -- Check 1: stg_file_qa_forms.sections — top-level type
  SELECT 'qa_forms.sections_type' AS check_name,
         CASE WHEN data_type LIKE 'ARRAY<STRUCT%' THEN 'PASS' ELSE 'FAIL' END AS status,
         data_type AS detail
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_qa_forms'
    AND  column_name = 'sections'
    AND  field_path = 'sections'

  UNION ALL

  -- Check 1b: sections sub-field count = 3
  SELECT 'qa_forms.sections_subfield_count',
         CASE WHEN cnt = 3 THEN 'PASS' ELSE 'FAIL' END,
         CAST(cnt AS STRING) || ' sub-fields (expected 3)'
  FROM (
    SELECT COUNT(*) AS cnt
    FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
    WHERE  table_name = 'stg_file_qa_forms'
      AND  column_name = 'sections'
      AND  field_path LIKE 'sections.%'
  )

  UNION ALL

  -- Check 1c: sections.section_code is STRING
  SELECT 'qa_forms.sections.section_code',
         CASE WHEN data_type = 'STRING' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_qa_forms'
    AND  field_path = 'sections.section_code'

  UNION ALL

  -- Check 1d: sections.max_points is INT64
  SELECT 'qa_forms.sections.max_points',
         CASE WHEN data_type = 'INT64' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_qa_forms'
    AND  field_path = 'sections.max_points'

  UNION ALL

  -- Check 1e: sections.scored_points is INT64
  SELECT 'qa_forms.sections.scored_points',
         CASE WHEN data_type = 'INT64' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_qa_forms'
    AND  field_path = 'sections.scored_points'

  UNION ALL

  -- Check 2: stg_file_chat_transcripts.messages — top-level type
  SELECT 'chat_transcripts.messages_type',
         CASE WHEN data_type LIKE 'ARRAY<STRUCT%' THEN 'PASS' ELSE 'FAIL' END,
         data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  column_name = 'messages'
    AND  field_path = 'messages'

  UNION ALL

  -- Check 2b: messages sub-field count = 3
  SELECT 'chat_transcripts.messages_subfield_count',
         CASE WHEN cnt = 3 THEN 'PASS' ELSE 'FAIL' END,
         CAST(cnt AS STRING) || ' sub-fields (expected 3)'
  FROM (
    SELECT COUNT(*) AS cnt
    FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
    WHERE  table_name = 'stg_file_chat_transcripts'
      AND  column_name = 'messages'
      AND  field_path LIKE 'messages.%'
  )

  UNION ALL

  -- Check 2c: messages.sender is STRING
  SELECT 'chat_transcripts.messages.sender',
         CASE WHEN data_type = 'STRING' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  field_path = 'messages.sender'

  UNION ALL

  -- Check 2d: messages.ts_ms is INT64
  SELECT 'chat_transcripts.messages.ts_ms',
         CASE WHEN data_type = 'INT64' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  field_path = 'messages.ts_ms'

  UNION ALL

  -- Check 2e: messages.text is STRING
  SELECT 'chat_transcripts.messages.text',
         CASE WHEN data_type = 'STRING' THEN 'PASS' ELSE 'FAIL' END,
         'type=' || data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  field_path = 'messages.text'

  UNION ALL

  -- Check 3: stg_file_chat_transcripts.metadata — JSON
  SELECT 'chat_transcripts.metadata_type',
         CASE WHEN data_type = 'JSON' THEN 'PASS' ELSE 'FAIL' END,
         data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  column_name = 'metadata'
    AND  field_path = 'metadata'

  UNION ALL

  -- Check 4: stg_file_speech_analytics.keywords — ARRAY<STRING>
  SELECT 'speech_analytics.keywords_type',
         CASE WHEN data_type = 'ARRAY<STRING>' THEN 'PASS' ELSE 'FAIL' END,
         data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_speech_analytics'
    AND  column_name = 'keywords'
    AND  field_path = 'keywords'
),

summary AS (
  SELECT COUNT(*) AS total_checks,
         SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS passed,
         SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS failed
  FROM   checks
)

-- Show failures first, then passes, then summary
SELECT check_name, status, detail
FROM   checks
UNION ALL
SELECT 'OVERALL',
       CASE WHEN s.failed = 0 THEN 'PASS' ELSE 'FAIL' END,
       'checked ' || CAST(s.total_checks AS STRING) || ' complex-type assertions, '
       || CAST(s.passed AS STRING) || ' passed, ' || CAST(s.failed AS STRING) || ' failed'
FROM   summary s
ORDER  BY CASE WHEN status = 'FAIL' THEN 0 ELSE 1 END, check_name;
