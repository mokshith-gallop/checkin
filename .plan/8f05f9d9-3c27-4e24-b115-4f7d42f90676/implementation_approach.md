# Implementation Approach

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
