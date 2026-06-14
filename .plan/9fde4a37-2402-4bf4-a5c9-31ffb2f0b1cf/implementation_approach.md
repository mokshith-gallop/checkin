# Implementation Approach

## Implementation Approach: BigQuery DDL Generation for 100 Tables + 15 Views

### Overall Strategy
Generate BigQuery `CREATE TABLE` / `CREATE VIEW` DDL by systematically translating each Hive source DDL file (02–09 `.hql`) using the `manifests/tables.yaml` as the canonical schema reference. Output is organized into three dataset subdirectories (`bigquery/ddl/staging/`, `bigquery/ddl/ods/`, `bigquery/ddl/dm/`), one `.sql` file per table/view.

### Existing Pattern (Follow Exactly)
The existing `bigquery/ddl/staging/stg_crm_contract.sql` establishes the canonical DDL pattern:
- **Header comment block**: documents the source Hive DDL, conversion notes, and column count reconciliation
- **`CREATE TABLE IF NOT EXISTS dataset.table_name`** (not `CREATE OR REPLACE`)
- **Hive-specific clauses dropped**: `EXTERNAL`, `STORED AS`, `LOCATION`, `TBLPROPERTIES`, `ROW FORMAT`, `SERDE`, `CLUSTERED BY`
- **Partition columns inlined** into the column list (not separate)
- **Partition type adjustment**: Hive `STRING` partition columns become `DATE` where the downstream consumers treat them as dates (e.g., `load_date`, `snapshot_date`, `event_date`, `call_date`, `sched_date`)
- **Column descriptions** via `OPTIONS(description = '...')` for legacy trap documentation
- **No `NOT NULL` constraints** on any column (MERGE-target compatibility per AC #4)

### DDL Organization — 118 Files Total

| Directory | Count | Contents |
|---|---|---|
| `bigquery/ddl/staging/` | 45 files | Sqoop mirrors (27), delta feeds (8), file feeds (10) |
| `bigquery/ddl/ods/` | 30 files | Cleansed (15), delta-merged (8), SCD-2 (3), ACID (4) |
| `bigquery/ddl/dm/` | 40 files | Dimensions (9), facts (9), aggregates (7), views (15) |
| **Total** | **115** | 100 tables + 15 views |

Plus 3 orchestration files:
- `bigquery/ddl/00-create-datasets.sql` — `CREATE SCHEMA IF NOT EXISTS staging/ods/dm`
- `bigquery/ddl/run-all-ddl.sh` — shell script executing all DDL files via `bq query --nouse_legacy_sql` in dependency order
- `bigquery/ddl/README.md` — documents conventions, type mapping, and partitioning decisions

### Type Mapping Rules

| Hive Type | BigQuery Type | Notes |
|---|---|---|
| `BIGINT` | `INT64` | |
| `INT` | `INT64` | BigQuery has no INT32 |
| `SMALLINT` | `INT64` | |
| `STRING` | `STRING` | |
| `BOOLEAN` | `BOOL` | |
| `DOUBLE` | `FLOAT64` | |
| `TIMESTAMP` | `TIMESTAMP` | UTC-only |
| `DATE` | `DATE` | |
| `DECIMAL(p,s)` | `NUMERIC(p,s)` | All 12 precision/scale pairs fit within NUMERIC(38,9) |
| `ARRAY<STRUCT<...>>` | `ARRAY<STRUCT<...>>` | Native BigQuery support |
| `ARRAY<STRING>` | `ARRAY<STRING>` | REPEATED STRING |
| `MAP<STRING,STRING>` | `JSON` | Per user decision — for `stg_file_chat_transcripts.metadata` |

### Partitioning Translation

| Layer | Hive Partition Type | BigQuery Partition | Example |
|---|---|---|---|
| Staging (sqoop mirrors) | `load_date STRING` | `PARTITION BY load_date` (type changed to `DATE`) | `stg_crm_client` |
| Staging (deltas) | `extract_ts STRING` | `PARTITION BY extract_date` (derived `DATE` column replacing STRING) | `stg_fin_timesheet_delta` |
| Staging (file feeds) | `client_code STRING, feed_date STRING` | `PARTITION BY feed_date` (DATE), `client_code` becomes a regular column + clustering column | Multi-column partition → single partition + cluster |
| ODS (cleanse) | `snapshot_date/event_date/call_date/sched_date STRING` | `PARTITION BY <col>` (type changed to `DATE`) | `ods_program` |
| ODS (delta-merge) | `work_month/period_month/swap_month/event_month STRING` | `PARTITION BY <col>` (keep as `STRING`, use pseudo-column partition or leave unpartitioned if too few distinct values) | `ods_timesheet` |
| ODS (SCD-2) | `eff_from_year INT` | `PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2026, 1))` | `ods_agent_scd2` |
| ODS (ACID) | none | Unpartitioned (small tables, MERGE targets) | `ods_client_acid` |
| DM (dimensions) | none | Unpartitioned (small) | `dim_agent` |
| DM (facts) | `date_key INT` | `PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20251231, 1))` | `fact_interaction` |
| DM (facts) | `date_key INT, channel STRING` | `PARTITION BY RANGE_BUCKET(date_key, ...)` + `CLUSTER BY channel` (multi-col partition → single + cluster) | `fact_interaction` |
| DM (facts) | `period_month STRING` | `PARTITION BY period_month` — keep as STRING pseudo-partition or unpartitioned | `fact_billing_line` |
| DM (aggs) | `date_key INT` | Same as facts | `agg_agent_daily` |
| DM (aggs) | `period_month STRING` | Same as facts | `agg_program_monthly` |
| DM (aggs) | `week_start_key INT` | `PARTITION BY RANGE_BUCKET(week_start_key, GENERATE_ARRAY(20200101, 20251231, 1))` | `agg_agent_weekly` |

### Clustering Strategy
- `fact_interaction`: `CLUSTER BY channel, agent_sk, client_sk` (channel demoted from 2nd partition)
- `fact_billing_line`: `CLUSTER BY client_sk, program_sk`
- Staging file feeds: `CLUSTER BY client_code` (demoted from partition)
- `stg_tel_call`: `CLUSTER BY call_id` (replaces CLUSTERED BY bucketing)
- ACID tables: `CLUSTER BY <pk>` (replaces CLUSTERED BY bucketing)

### Special Handling Per Acceptance Criteria

1. **Epoch columns in staging (AC #2)**: Remain `INT64`. Column descriptions document the encoding: `'epoch SECONDS (legacy)'`, `'epoch MILLISECONDS (legacy)'`, or `'Oracle string YYYYMMDDHH24MISS (legacy)'`. The 2 lie_ms columns (`issued_ts_sec`, `due_ts_sec`) carry: `'WARNING: column name says seconds but VALUES ARE MILLISECONDS. All consumers divide by 1000. See EPOCH-POLICY.md.'`

2. **Epoch columns in ODS/DM (AC #2)**: All epoch-derived columns are `TIMESTAMP` (not INT64/STRING). The conversion happens in the cleanse SQL scripts, not in the DDL.

3. **Complex types (AC #3)**:
   - `stg_file_qa_forms.sections` → `ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>`
   - `stg_file_chat_transcripts.messages` → `ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>`
   - `stg_file_chat_transcripts.metadata` → `JSON` (with description: `'MAP<STRING,STRING> from Hive — represented as JSON in BigQuery'`)
   - `stg_file_speech_analytics.keywords` → `ARRAY<STRING>`

4. **ACID tables (AC #4)**: Created as native (non-external) BigQuery tables. No ORC/transactional properties. No `NOT NULL` constraints (MERGE-compatible). Clustering by PK replaces CLUSTERED BY bucketing.

5. **SCD-2 surrogate keys (AC #5)**: Columns typed as `STRING` with description: `'Surrogate key: TO_HEX(MD5(CONCAT(CAST(<business_key> AS STRING), ''|'', CAST(eff_from_ts AS STRING))))'`

6. **Format-specific tables (AC #6)**: All created as native BigQuery tables. Table-level `OPTIONS(description = ...)` documents the original format:
   - RegexSerDe tables: `'Source: Hive RegexSerDe — pre-processed to structured format before BQ load'`
   - SequenceFile/RCFile: `'Source: Hive SequenceFile/RCFile — converted to Parquet/JSON for BQ load'`
   - JsonSerDe tables: `'Source: Hive JsonSerDe — loaded as NEWLINE_DELIMITED_JSON'`
   - TextFile pipe-delimited: `'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter'`

7. **DECIMAL precision (AC #7)**: All 12 source precision/scale pairs map to `NUMERIC(p,s)`. None exceed NUMERIC(38,9). No widening.

### Views (15)
All 15 views are `CREATE VIEW IF NOT EXISTS dm.<view_name> AS ...` with SQL translated per the locked SQL Dialect Translation Strategy:
- `NDV()` → `APPROX_COUNT_DISTINCT()`
- `GROUPING__ID` → `GROUPING()` with bit-order remapping
- `RLIKE` → `REGEXP_CONTAINS()`
- `regexp_extract()` → `REGEXP_EXTRACT()`
- `unix_timestamp(ts)` → `UNIX_SECONDS(ts)`
- `from_unixtime()` → `TIMESTAMP_SECONDS()`
- `date_add(ts, 7)` → `TIMESTAMP_ADD(ts, INTERVAL 7 DAY)`
- Recursive CTE (`vw_org_hierarchy`) → supported natively in BigQuery

### Execution Order
The `run-all-ddl.sh` script executes in this order:
1. `00-create-datasets.sql` (create 3 datasets)
2. All staging tables (no dependencies)
3. All ODS tables (no dependencies on other DDL — dependencies are runtime)
4. All DM tables (no dependencies on other DDL)
5. All DM views (depend on tables existing in all 3 datasets)
