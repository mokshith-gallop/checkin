-- bigquery/ddl/ods/ods_survey_response.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_survey_response (...)
--   PARTITIONED BY (event_date STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch millis cast in cleanse).
--   - Hive PARTITIONED BY (event_date STRING) → inlined DATE column +
--     PARTITION BY event_date.
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_survey_response (
  survey_id          STRING,
  client_code        STRING,
  interaction_ref    STRING,
  survey_ts          TIMESTAMP,
  csat_score         INT64,
  nps_score          INT64,
  fcr_claimed        BOOL,
  verbatim           STRING,
  event_date         DATE
)
PARTITION BY event_date;
