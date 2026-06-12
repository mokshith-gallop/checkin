# Locked Decisions for Story 8f05f9d9-3c27-4e24-b115-4f7d42f90676

## Implementation Approach
## Implementation Approach: Convert 33 Cleanse/Dim/Fact Scripts to BigQuery SQL

### Scope
Convert 15 cleanse scripts (09–23), 9 dim-load scripts (41–49), and 9 fact-load scripts (50–58) from Impala/Hive dialect to BigQuery Standard SQL. This is a strict 1:1 port — no logic refactoring, no layer-skip fixes.

### Script Categories & Patterns

**A. 15 Cleanse Scripts (09–23) → Partition-scoped writes to `ods.*`**

All follow the same template:
1. `INSERT OVERWRITE TABLE ods.X PARTITION (partition_col)` → **DELETE + INSERT** within a scripting block
2. PK dedup via `ROW_NUMBER() OVER (PARTITION BY pk ORDER BY ts DESC) ... WHERE rn = 1` → preserved as-is (BigQuery supports `ROW_NUMBER()` natively)
3. String cleansing `UPPER(TRIM(...))` → preserved as-is
4. `COMPUTE INCREMENTAL STATS` → dropped entirely

Sub-patterns by epoch encoding:
| Scripts | Source encoding | Hive function | BigQuery replacement |
|---|---|---|---|
| 09, 12, 13, 14, 15, 16 | Epoch seconds | `from_unixtime(x)` | `TIMESTAMP_SECONDS(x)` |
| 17, 18, 20, 21, 23 | Epoch millis | `from_unixtime(CAST(x/1000 AS BIGINT))` | `TIMESTAMP_MILLIS(x)` |
| 10, 11 | String YYYYMMDDHHMMSS | `unix_timestamp(x, 'yyyyMMddHHmmss')` | `PARSE_TIMESTAMP('%Y%m%d%H%M%S', x)` |
| 19 | Epoch seconds (email) | `from_unixtime(x)` | `TIMESTAMP_SECONDS(x)` |
| 22 | No epoch casting (reads ODS) | n/a | n/a |

Special patterns in cleanse scripts:
- **17-cleanse-ivr-session**: `group_concat(e.menu_path, ' > ')` → `STRING_AGG(e.menu_path, ' > ')`. Also uses `ROW_NUMBER()` subquery for `exit_key` extraction.
- **18-cleanse-chat-session**: Impala nested-collection syntax `FROM t, t.messages m` → `FROM t CROSS JOIN UNNEST(t.messages) AS m`
- **21-cleanse-qa-evaluation**: Impala nested-collection syntax `FROM f, f.sections s` → `FROM f CROSS JOIN UNNEST(f.sections) AS s`
- **10-cleanse-contract**: `unix_timestamp(s.end_dt, 'yyyyMMddHHmmss')` on nullable `end_dt` → `PARSE_TIMESTAMP('%Y%m%d%H%M%S', s.end_dt)` — NULLs propagate naturally (PARSE_TIMESTAMP returns NULL for NULL input)
- **22-cleanse-interaction**: UNION ALL across 3 ODS sources + LEFT JOIN to staging; uses `unix_timestamp(ts)` for handle_seconds calc → `UNIX_SECONDS(CAST(ts AS TIMESTAMP))`

**B. 9 Dim-Load Scripts (41–49) → Full-table overwrites to `dm.*`**

All unpartitioned dimension tables use **`CREATE OR REPLACE TABLE dm.X AS SELECT ...`** pattern.

| Script | Target | Special pattern |
|---|---|---|
| 41-load-dim-date | `dm.dim_date` | `LOAD DATA INPATH` → replace with `bq load` from GCS-staged parquet, or `CREATE OR REPLACE TABLE dm.dim_date AS SELECT * FROM EXTERNAL_TABLE_ON_GCS` |
| 42-load-dim-agent | `dm.dim_agent` | Reads SCD-2 + ACID tables (pre-loaded fixtures per AC#1); `from_unixtime(unix_timestamp(ac.hire_ts), 'yyyyMMdd')` → `CAST(FORMAT_TIMESTAMP('%Y%m%d', ac.hire_ts) AS INT64)` |
| 43-load-dim-client | `dm.dim_client` | Reads ACID table |
| 44-load-dim-program | `dm.dim_program` | Reads ODS + contract for billing_model; date_key formatting |
| 45-load-dim-queue | `dm.dim_queue` | Simple ODS read |
| 46-load-dim-site | `dm.dim_site` | Hardcoded CASE for region/country/timezone — preserve as-is |
| 47-load-dim-shift | `dm.dim_shift` | Simple ODS read |
| 48-load-dim-org | `dm.dim_org` | Org hierarchy flattening (self-join 4 levels) |
| 49-load-dim-disposition | `dm.dim_disposition` | Simple staging read (layer-skip) |

**C. 9 Fact-Load Scripts (50–58) → Partition-scoped writes to `dm.*`**

All partitioned fact tables use **DELETE + INSERT** scoped to the `run_date` partition.

| Script | Target | Partition col | Special patterns |
|---|---|---|---|
| 50-load-fact-interaction | `dm.fact_interaction` | `date_key` (INT, was multi-col with `channel`) | `channel` becomes clustering col; LEFT JOINs default to -1 for orphan FKs; `from_unixtime(unix_timestamp(ts), 'yyyyMMdd')` → `CAST(FORMAT_TIMESTAMP('%Y%m%d', ts) AS INT64)` |
| 51-load-fact-agent-activity | `dm.fact_agent_activity` | `date_key` | **Layer-skip**: reads `staging.stg_tel_agent_state_event` with raw epoch arithmetic — preserve exactly |
| 52-load-fact-queue-interval | `dm.fact_queue_interval` | `date_key` | **Layer-skip**: reads `staging.stg_crm_sla_target`; 30-min interval bucketing via `floor(unix_timestamp()/1800)*1800` → `TIMESTAMP_SECONDS(CAST(FLOOR(UNIX_SECONDS(c.start_ts) / 1800) * 1800 AS INT64))` |
| 53-load-fact-csat-survey | `dm.fact_csat_survey` | `date_key` | Dimension lookups with -1 defaults |
| 54-load-fact-qa-evaluation | `dm.fact_qa_evaluation` | `date_key` | Dimension lookups |
| 55-load-fact-billing-line | `dm.fact_billing_line` | `period_month` | **Layer-skip**: reads `staging.stg_fin_invoice_line` with uncleansed `created_ms`; partition filter uses `substr(run_date, 1, 7)` → `FORMAT_DATE('%Y-%m', run_date)` |
| 56-load-fact-adherence-daily | `dm.fact_adherence_daily` | `date_key` | **Layer-skip**: reads `staging.stg_wfm_timeoff_request`; `unix_timestamp(sched_date, 'yyyy-MM-dd')` → `CAST(FORMAT_DATE('%Y%m%d', CAST(s.sched_date AS DATE)) AS INT64)` |
| 57-load-fact-ticket | `dm.fact_ticket` | `date_key` | **Layer-skip**: reads `staging.stg_tkt_ticket_event` + `stg_tkt_category`; resolution_minutes via epoch diff |
| 58-load-fact-ivr-path | `dm.fact_ivr_path` | `date_key` | Reads cleansed ODS; duration_seconds via `unix_timestamp()` diff → `UNIX_SECONDS(CAST(ts AS TIMESTAMP))` diff |

### Parameterization
Every script opens with:
```sql
DECLARE run_date DATE DEFAULT CURRENT_DATE();
```
All `${var:run_date}` references become `run_date`. Airflow can prepend `SET run_date = DATE '2024-01-15';` before execution.

For `fact_billing_line`, which filters on `period_month`, derive it:
```sql
DECLARE period_month STRING DEFAULT FORMAT_DATE('%Y-%m', run_date);
```

### Write Pattern Summary

| Target type | Write pattern | Scripts |
|---|---|---|
| ODS partitioned tables | `DELETE FROM ods.X WHERE partition_col = run_date; INSERT INTO ods.X SELECT ...;` | 09–23 (15 scripts) |
| DM dimensions (unpartitioned) | `CREATE OR REPLACE TABLE dm.X AS SELECT ...;` | 42–49 (8 scripts) |
| DM dim_date | `bq load` or external table from GCS parquet | 41 (1 script) |
| DM facts (partitioned by date_key) | `DELETE FROM dm.X WHERE date_key = date_key_val; INSERT INTO dm.X SELECT ...;` | 50–54, 56–58 (8 scripts) |
| DM fact_billing_line (partitioned by period_month) | `DELETE FROM dm.X WHERE period_month = period_month_val; INSERT INTO dm.X SELECT ...;` | 55 (1 script) |

### Universal Removals
These Impala/Hive constructs are dropped from every script:
- `COMPUTE [INCREMENTAL] STATS` — BigQuery auto-manages statistics
- `INVALIDATE METADATA` / `REFRESH` — not applicable
- `/* +STRAIGHT_JOIN */` hints — BigQuery optimizer handles this
- `STORED AS PARQUET` / `TBLPROPERTIES` — BigQuery uses Capacitor format internally

### Function Mapping Reference (all scripts)

| Hive/Impala | BigQuery | Used in scripts |
|---|---|---|
| `from_unixtime(x)` | `TIMESTAMP_SECONDS(x)` | 09,12,13,14,15,16,19,51 |
| `from_unixtime(CAST(x/1000 AS BIGINT))` | `TIMESTAMP_MILLIS(x)` | 17,18,20,21,23 |
| `from_unixtime(x, 'yyyyMMdd')` | `FORMAT_TIMESTAMP('%Y%m%d', TIMESTAMP_SECONDS(x))` | 42,44,50-58 |
| `unix_timestamp(ts, fmt)` | `UNIX_SECONDS(PARSE_TIMESTAMP(fmt_bq, ts))` | 10,11,56 |
| `unix_timestamp(ts)` | `UNIX_SECONDS(CAST(ts AS TIMESTAMP))` | 22,52,57,58 |
| `PARSE_TIMESTAMP` (for string dates) | `PARSE_TIMESTAMP('%Y%m%d%H%M%S', x)` | 10,11 |
| `to_date(ts)` | `DATE(ts)` | 16,17,18,20,21,22,23 |
| `group_concat(col, sep)` | `STRING_AGG(col, sep)` | 17 |
| `FROM t, t.nested_col alias` | `FROM t CROSS JOIN UNNEST(t.nested_col) AS alias` | 18,21 |
| `CAST(x AS INT)` | `CAST(x AS INT64)` | throughout |
| `CAST(x AS DECIMAL(p,s))` | `CAST(x AS NUMERIC)` | 21,52,56 |
| `CONCAT('V', CAST(id AS STRING))` | same (BigQuery-compatible) | 22 |
| `UPPER(TRIM(...))` | same (BigQuery-compatible) | 09-15 |

### dim_date Loading Strategy (Script 41)
`LOAD DATA INPATH` has no BigQuery equivalent. Replace with:
```sql
-- Option: bq load from GCS
-- bq load --source_format=PARQUET dm.dim_date gs://nbcs-data/incoming/dim_date/*.parquet
```
Or use a BigQuery external table pointing to the GCS parquet, then:
```sql
CREATE OR REPLACE TABLE dm.dim_date AS
SELECT * FROM EXTERNAL_QUERY_OR_TABLE;
```

### File Organization
Output converted scripts to `/workspace/project/bigquery/` maintaining the numeric prefix naming:
```
bigquery/
  09-cleanse-program.sql
  10-cleanse-contract.sql
  ...
  23-cleanse-dialer-attempt.sql
  41-load-dim-date.sql
  42-load-dim-agent.sql
  ...
  49-load-dim-disposition.sql
  50-load-fact-interaction.sql
  ...
  58-load-fact-ivr-path.sql
```

### Execution Dependencies
Scripts must run in this order (matching the Oozie `wf-ods-dm-build` chain):
1. **Cleanse** (09–23) — can run in parallel within group
2. **Dims** (41–49) — must follow cleanse; can run in parallel within group (except 42 depends on SCD-2/ACID fixtures)
3. **Facts** (50–58) — must follow dims; can run in parallel within group

## Validation
## Validation Strategy: 33 Converted Scripts

### Acceptance Criteria Coverage

Each of the 8 acceptance criteria maps to specific test assertions:

---

**AC#1 — Schema match (all 33 tables populated, INFORMATION_SCHEMA matches DDL)**

- For each of the 33 target tables, after running the converted script against the datagen staging seed:
  - `SELECT COUNT(*) FROM {dataset}.{table}` > 0
  - `SELECT column_name, data_type FROM {dataset}.INFORMATION_SCHEMA.COLUMNS WHERE table_name = '{table}' ORDER BY ordinal_position` matches the BigQuery DDL column list with 0 mismatches in count or type
- SCD-2/ACID fixture tables (`ods_agent_scd2`, `ods_client_acid`, `ods_invoice_acid`, `ods_ticket_acid`, `ods_rate_card`) must be pre-loaded into the scratch dataset before any script runs

---

**AC#2 — PK dedup (row count = COUNT(DISTINCT pk), latest-timestamp survivor)**

Applies to all 15 cleanse scripts (09–23). For each:
```sql
-- Row count assertion
ASSERT (
  SELECT COUNT(*) FROM ods.{table} WHERE {partition_col} = run_date
) = (
  SELECT COUNT(DISTINCT {pk_col}) FROM staging.{source_table} WHERE {date_filter} = run_date
);
```
- Additionally, for each duplicated PK, assert the surviving row has the latest ordering timestamp (matches the `ROW_NUMBER() ... ORDER BY ts DESC` semantics)
- Test with the ~0.5% deliberately duplicated PKs in the datagen seed

---

**AC#3 — Epoch conversion accuracy (0-second drift, UTC)**

Test boundary epochs across both seconds and millis tables:

| Test epoch | Seconds value | Millis value | Expected UTC timestamp |
|---|---|---|---|
| Unix epoch zero | 0 | 0 | `1970-01-01 00:00:00 UTC` |
| Y2K | 946684800 | 946684800000 | `2000-01-01 00:00:00 UTC` |
| End of 2099 | 4102444799 | 4102444799000 | `2099-12-31 23:59:59 UTC` |

For each cleanse script that performs epoch casting:
```sql
-- Verify TIMESTAMP_SECONDS output
ASSERT TIMESTAMP_SECONDS(946684800) = TIMESTAMP '2000-01-01 00:00:00 UTC';
-- Verify TIMESTAMP_MILLIS output
ASSERT TIMESTAMP_MILLIS(946684800000) = TIMESTAMP '2000-01-01 00:00:00 UTC';
```

Insert test rows with these boundary values into staging, run the cleanse script, and verify the ODS output matches with 0-second drift. Confirm no implicit local-timezone conversion by checking the output is identical regardless of BigQuery session timezone settings.

---

**AC#4 — String date parsing (contract tables, NULL propagation)**

For script 10-cleanse-contract:
```sql
-- Insert test contract with known string dates and NULL end_dt
-- Run converted script
-- Assert:
ASSERT (SELECT start_ts FROM ods.ods_contract WHERE contract_id = {test_id})
  = PARSE_TIMESTAMP('%Y%m%d%H%M%S', '20230615143022');  -- exact match

ASSERT (SELECT end_ts FROM ods.ods_contract WHERE contract_id = {test_null_id})
  IS NULL;  -- NULL propagation

ASSERT (SELECT signed_ts FROM ods.ods_contract WHERE contract_id = {test_id})
  = PARSE_TIMESTAMP('%Y%m%d%H%M%S', '{expected_signed_dt}');
```

Also validate script 11-cleanse-contract-line's `effective_dt` parsing with the same pattern.

---

**AC#5 — Nested collection UNNEST + STRING_AGG**

Three scripts with special syntax:

**18-cleanse-chat-session** (UNNEST):
```sql
-- Verify per-session message counts match legacy
-- Legacy: FROM t, t.messages m → BigQuery: CROSS JOIN UNNEST(t.messages) AS m
ASSERT (
  SELECT SUM(message_count) FROM ods.ods_chat_session WHERE event_date = run_date
) = (
  SELECT COUNT(*) FROM staging.stg_file_chat_transcripts t
  CROSS JOIN UNNEST(t.messages) AS m WHERE t.feed_date = run_date
);
```

**21-cleanse-qa-evaluation** (UNNEST):
```sql
-- Verify per-form section sums match
-- section_count, scored_points, max_points must equal aggregation over UNNEST(sections)
ASSERT (
  SELECT SUM(section_count) FROM ods.ods_qa_evaluation WHERE event_date = run_date
) = (
  SELECT COUNT(*) FROM staging.stg_file_qa_forms f
  CROSS JOIN UNNEST(f.sections) AS s WHERE f.feed_date = run_date
);
```

**17-cleanse-ivr-session** (STRING_AGG):
```sql
-- Verify menu_path_full concatenation matches legacy group_concat output
-- STRING_AGG(menu_path, ' > ') should produce identical row-for-row output
-- Compare by session_ref: every session's menu_path_full must match
```

---

**AC#6 — fact_interaction FK defaults and partitioning**

```sql
-- Orphan FK test: rows with unresolvable agent/queue land with sk = -1
ASSERT (
  SELECT COUNT(*) FROM dm.fact_interaction
  WHERE date_key = {run_date_key} AND (agent_sk = -1 OR queue_sk = -1)
) = (
  SELECT COUNT(*) FROM ods.ods_interaction i
  WHERE i.event_date = run_date
    AND (i.agent_id NOT IN (SELECT agent_id FROM dm.dim_agent WHERE is_current)
         OR i.queue_id NOT IN (SELECT queue_id FROM dm.dim_queue))
);

-- Total row count matches ODS interaction count for the run_date
ASSERT (
  SELECT COUNT(*) FROM dm.fact_interaction WHERE date_key = {run_date_key}
) = (
  SELECT COUNT(*) FROM ods.ods_interaction WHERE event_date = run_date
);

-- Partitioning: verify table is partitioned on date_key column
-- (check via INFORMATION_SCHEMA.PARTITIONS or table metadata)

-- Clustering: verify clustering keys are channel, agent_sk (+ client_sk per locked decision)
```

---

**AC#7 — dim_date load (LOAD DATA INPATH replacement)**

```sql
-- After bq load / external table load:
-- Full outer join anti-match = 0 differences
ASSERT (
  SELECT COUNT(*) FROM (
    SELECT * FROM dm.dim_date
    EXCEPT DISTINCT
    SELECT * FROM {source_parquet_table}
    UNION ALL
    SELECT * FROM {source_parquet_table}
    EXCEPT DISTINCT
    SELECT * FROM dm.dim_date
  )
) = 0;
```

---

**AC#8 — run_date parameterization (partition isolation)**

```sql
-- Run script with run_date = '2024-01-15' → populates partition 20240115
-- Run script with run_date = '2024-01-16' → populates partition 20240116
-- Assert: partition 20240115 row count unchanged after second run
ASSERT (
  SELECT COUNT(*) FROM dm.{table} WHERE date_key = 20240115
) = {count_after_first_run};

-- Assert: partition 20240116 has rows from second run
ASSERT (
  SELECT COUNT(*) FROM dm.{table} WHERE date_key = 20240116
) > 0;
```

This test applies to all 24 partition-scoped scripts (15 cleanse + 9 fact). For `CREATE OR REPLACE TABLE` dimension scripts, this AC is inherently satisfied (dims are unpartitioned, always fully rebuilt).

---

### Test Execution Approach

1. **Pre-requisites**: Load datagen staging seed + SCD-2/ACID fixtures into a scratch BigQuery project/dataset
2. **Test ordering**: Cleanse → Dims → Facts (matching the pipeline execution order)
3. **Assertion mechanism**: BigQuery scripting `ASSERT` statements appended to each converted script, or a separate `test_*.sql` file per script
4. **Boundary epoch injection**: Insert the 3 boundary epochs (0, 946684800, 4102444799) and their millis equivalents into the relevant staging tables before running cleanse scripts
5. **Duplicate PK injection**: Already present in datagen seed (~0.5%)
6. **Orphan FK injection**: Already present in datagen seed (~0.2%)

### Edge Cases

- **Out-of-range epochs** (~1% in staging): Use `SAFE.TIMESTAMP_SECONDS()` / `SAFE.TIMESTAMP_MILLIS()` in ODS scripts to produce NULL; DQ check (script 78) flags them
- **NULL handling in PARSE_TIMESTAMP**: `PARSE_TIMESTAMP('%Y%m%d%H%M%S', NULL)` returns NULL — validates AC#4's NULL propagation requirement
- **STRING_AGG ordering**: `STRING_AGG` in BigQuery has no guaranteed order unless `ORDER BY` is specified. For `17-cleanse-ivr-session`, the legacy `group_concat` also had no guaranteed order (documented as "known wart"). Validate that the concatenated values contain the same set of menu paths, not necessarily the same order.
- **DECIMAL precision**: `CAST(x AS DECIMAL(5,2))` in Hive → `CAST(x AS NUMERIC)` in BigQuery. BigQuery NUMERIC has higher precision (38 digits) — values will match but storage differs. No functional impact.
- **Boolean expressions**: Impala `(NOT c.abandoned_flag AND c.talk_seconds > 0)` works directly in BigQuery — no conversion needed.
