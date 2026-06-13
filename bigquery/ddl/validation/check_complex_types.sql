-- =============================================================================
-- check_complex_types.sql — AC #3: Complex type validation
--
-- Verifies ARRAY<STRUCT>, ARRAY<STRING>, and JSON columns via
-- INFORMATION_SCHEMA.COLUMN_FIELD_PATHS.
--
-- Expected:
--   stg_file_qa_forms.sections       → ARRAY<STRUCT<...>> with 3 sub-fields
--   stg_file_chat_transcripts.messages → ARRAY<STRUCT<...>> with 3 sub-fields
--   stg_file_chat_transcripts.metadata → JSON
--   stg_file_speech_analytics.keywords → ARRAY<STRING>
--
-- Usage:
--   bq query --nouse_legacy_sql < check_complex_types.sql
-- =============================================================================

WITH checks AS (
  -- Check 1: stg_file_qa_forms.sections — ARRAY<STRUCT<...>> with 3 sub-fields
  SELECT 'qa_forms.sections_type' AS check_name,
         CASE WHEN data_type LIKE 'ARRAY<STRUCT%' THEN 'PASS' ELSE 'FAIL' END AS status,
         data_type AS detail
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_qa_forms'
    AND  column_name = 'sections'
    AND  field_path = 'sections'

  UNION ALL

  SELECT 'qa_forms.sections_subfields',
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

  -- Check 2: stg_file_chat_transcripts.messages — ARRAY<STRUCT<...>> with 3 sub-fields
  SELECT 'chat_transcripts.messages_type',
         CASE WHEN data_type LIKE 'ARRAY<STRUCT%' THEN 'PASS' ELSE 'FAIL' END,
         data_type
  FROM   staging.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
  WHERE  table_name = 'stg_file_chat_transcripts'
    AND  column_name = 'messages'
    AND  field_path = 'messages'

  UNION ALL

  SELECT 'chat_transcripts.messages_subfields',
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
)
SELECT check_name, status, detail
FROM   checks
ORDER  BY CASE WHEN status = 'FAIL' THEN 0 ELSE 1 END, check_name;
