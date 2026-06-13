-- bigquery/ddl/ods/ods_timesheet.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive):
--   CREATE TABLE IF NOT EXISTS ods.ods_timesheet (...)
--   PARTITIONED BY (work_month STRING)
--   STORED AS PARQUET
--   TBLPROPERTIES ('parquet.compression'='SNAPPY');
--
-- Conversion notes:
--   - STORED AS PARQUET, TBLPROPERTIES dropped (BigQuery managed table).
--   - Hive BIGINT → BigQuery INT64; Hive INT → BigQuery INT64.
--   - Hive BOOLEAN → BigQuery BOOL.
--   - Hive STRING  → BigQuery STRING.
--   - Hive TIMESTAMP → BigQuery TIMESTAMP (delta change_ms cast in merge).
--   - Hive PARTITIONED BY (work_month STRING) → inlined DATE column +
--     PARTITION BY work_month. Type changed from STRING ('YYYY-MM') to DATE
--     using first-of-month convention (e.g., '2024-01' → DATE '2024-01-01').
--   - Column count: 8 source columns + 1 inlined partition column = 9 total.

CREATE TABLE IF NOT EXISTS ods.ods_timesheet (
  timesheet_id        INT64,
  agent_id            INT64,
  work_date           STRING,
  program_id          INT64,
  billable_minutes    INT64,
  nonbillable_minutes INT64,
  approved_flag       BOOL,
  last_change_ts      TIMESTAMP,
  work_month          DATE
)
PARTITION BY work_month;
