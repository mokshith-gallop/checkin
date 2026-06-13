-- bigquery/ddl/ods/ods_attrition_event.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_attrition_event (...)
--   PARTITIONED BY (event_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (epoch seconds cast in merge).
--   - Hive PARTITIONED BY (event_month STRING) → inlined DATE column +
--     PARTITION BY event_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_attrition_event (
  attrition_event_id   INT64,
  agent_id             INT64,
  notice_ts            TIMESTAMP,
  last_day             STRING,
  attrition_type       STRING,
  reason_code          STRING,
  regrettable_flag     BOOL,
  last_change_ts       TIMESTAMP,
  event_month          DATE
)
PARTITION BY event_month;
