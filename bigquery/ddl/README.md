# BigQuery DDL — Hive-to-BigQuery Schema Migration

This directory contains **115 BigQuery DDL files** that faithfully reproduce the
100 Hive tables + 15 views from the NBCS legacy CDH warehouse in BigQuery
Standard SQL.

## File Layout

```
bigquery/ddl/
├── 00-create-datasets.sql          # CREATE SCHEMA for staging, ods, dm
├── run-all-ddl.sh                  # Orchestration script (dependency order)
├── README.md                       # This file
├── validation/                     # 11 acceptance-criteria SQL scripts
│   ├── check_column_counts.sql     # AC #1
│   ├── check_epoch_types.sql       # AC #2
│   ├── check_acid_tables.sql       # AC #3
│   ├── check_identifiers.sql       # AC #4
│   ├── check_scd2_keys.sql         # AC #5
│   ├── check_decimal_precision.sql # AC #6
│   ├── check_format_tables.sql     # AC #7
│   ├── check_complex_types.sql     # AC #8
│   ├── check_nullability.sql       # AC #9
│   ├── check_partition_types.sql   # AC #10
│   ├── check_comment_preservation.sql # AC #11
│   └── validate_all.sh            # Run all 11 checks
├── staging/                        # 45 tables
│   ├── stg_crm_client.sql          # Sqoop mirrors (27)
│   ├── stg_fin_timesheet_delta.sql # Delta feeds (8)
│   ├── stg_file_qa_forms.sql       # File feeds (10)
│   └── ...
├── ods/                            # 30 tables
│   ├── ods_program.sql             # Cleanse (15)
│   ├── ods_timesheet.sql           # Delta-merge (8)
│   ├── ods_agent_scd2.sql          # SCD-2 (3)
│   ├── ods_client_acid.sql         # ACID (4)
│   └── ...
└── dm/                             # 25 tables + 15 views = 40 files
    ├── dim_date.sql                # Dimensions (9)
    ├── fact_interaction.sql        # Facts (9)
    ├── agg_agent_daily.sql         # Aggregates (7)
    ├── vw_org_hierarchy.sql        # Views (15)
    └── ...
```

## Quick Start

```bash
# Deploy all DDL to a specific project
./run-all-ddl.sh --project my-gcp-project

# Dry run (list files without executing)
./run-all-ddl.sh --dry-run

# Run acceptance-criteria validation (after deployment)
./validation/validate_all.sh --project my-gcp-project
```

## DDL Conventions

Every file follows the canonical pattern established in `staging/stg_crm_contract.sql`:

1. **Header comment block**: documents the source Hive DDL, conversion notes,
   and column count reconciliation.
2. **`CREATE TABLE IF NOT EXISTS dataset.table_name`** — not `CREATE OR REPLACE`.
3. **Hive-specific clauses dropped**: `EXTERNAL`, `STORED AS`, `LOCATION`,
   `TBLPROPERTIES`, `ROW FORMAT`, `SERDE`, `CLUSTERED BY ... INTO N BUCKETS`.
4. **Partition columns inlined** into the column list (not separate).
5. **No `NOT NULL` constraints** on any column — ensures MERGE-target
   compatibility and safe data loads (AC #9).
6. **Column descriptions** via `OPTIONS(description = '...')` for all columns
   that have a Hive `COMMENT` (68 total).

---

## Type Mapping (Hive → BigQuery)

| Hive Type | BigQuery Type | Notes |
|---|---|---|
| `BIGINT` | `INT64` | Identical 64-bit signed range |
| `INT` | `INT64` | BigQuery has no INT32; widened |
| `SMALLINT` | `INT64` | Widened |
| `STRING` | `STRING` | Direct map |
| `BOOLEAN` | `BOOL` | Direct map |
| `DOUBLE` | `FLOAT64` | Direct map |
| `TIMESTAMP` | `TIMESTAMP` | UTC-only in BigQuery |
| `DATE` | `DATE` | Direct map |
| `DECIMAL(p,s)` | `NUMERIC(p,s)` | All 7 distinct pairs fit NUMERIC(38,9) |
| `ARRAY<STRUCT<...>>` | `ARRAY<STRUCT<...>>` | Native BigQuery support; INT sub-fields → INT64 |
| `ARRAY<STRING>` | `ARRAY<STRING>` | REPEATED STRING |
| `MAP<STRING,STRING>` | `JSON` | See MAP→JSON rationale below |

### MAP<STRING,STRING> → JSON Decision

**Decision**: Hive `MAP<STRING,STRING>` is represented as BigQuery `JSON`.

**Rationale**: BigQuery has no native `MAP` type. The two options were:
1. `ARRAY<STRUCT<key STRING, value STRING>>` — preserves structure but requires
   `UNNEST` + `WHERE key = '...'` for every key lookup.
2. `JSON` — natural key-value access via `JSON_VALUE(metadata, '$.key_name')`,
   accepts any valid JSON (matching MAP semantics), and integrates with BigQuery's
   JSON functions (`JSON_QUERY`, `JSON_EXTRACT_ARRAY`, etc.).

`JSON` was chosen because:
- The `metadata` column in `stg_file_chat_transcripts` is the only MAP column.
- Downstream consumers primarily do individual key lookups, not iteration.
- `JSON_VALUE(metadata, '$.key')` is syntactically cleaner than unnest+filter.
- BigQuery's JSON type is schema-on-read, matching Hive MAP's dynamic-key nature.

The column description documents the choice:
`'Hive MAP<STRING,STRING> represented as JSON. Query individual keys with JSON_VALUE(metadata, "$.key_name").'`

---

## DECIMAL Precision/Scale Inventory

The source Hive DDL uses 12 distinct `DECIMAL(p,s)` declarations across 52
columns. These collapse to **7 unique precision/scale pairs** in BigQuery
`NUMERIC(p,s)` because multiple columns share the same precision and scale.

All pairs fit within NUMERIC(38,9), so **no BIGNUMERIC is used anywhere**.

### The 7 Distinct Pairs

| BigQuery Type | Source Declarations | Example Columns |
|---|---|---|
| `NUMERIC(14,2)` | `DECIMAL(14,2)` × 5 columns | `total_amount`, `line_amount`, `billed_amount`, `net_revenue`, `est_margin` |
| `NUMERIC(12,4)` | `DECIMAL(12,4)` × 5 columns | `unit_rate`, `rate`, `old_rate`, `new_rate` |
| `NUMERIC(12,2)` | `DECIMAL(12,2)` × 7 columns | `min_commit`, `amount`, `credit_amount`, `charge_amount`, `qty`, `sla_credit_amount`, `telco_cost_amount` |
| `NUMERIC(10,4)` | `DECIMAL(10,4)` × 1 column | `target_value` |
| `NUMERIC(8,2)` | `DECIMAL(8,2)` × 8 columns | `required_fte`, `avg_speed_answer_sec`, `avg_handle_sec`, `avg_handle_seconds` |
| `NUMERIC(7,2)` | `DECIMAL(7,2)` × 1 column | `volume_variance_pct` |
| `NUMERIC(5,2)` | `DECIMAL(5,2)` × 10 columns | `penalty_pct`, `overall_pct`, `adherence_pct`, `occupancy_pct`, `sl_pct`, `pct_promoters`, `pct_detractors` |

### Why Not BIGNUMERIC?

BIGNUMERIC is only needed when precision > 38 or scale > 9. The largest source
declaration is `DECIMAL(14,2)` (p=14, s=2), well within NUMERIC limits. No
widening beyond source precision is applied.

---

## Partitioning Translation

BigQuery requires partition columns to be `DATE`, `TIMESTAMP`, `DATETIME`, or
`INT64` (for `RANGE_BUCKET`). **No STRING partitions** are created — every
Hive `STRING` partition column is converted to `DATE` or replaced with a
`RANGE_BUCKET` on an integer key.

### Complete Partition Mapping

| Source Pattern | BigQuery Translation | Tables |
|---|---|---|
| `PARTITIONED BY (load_date STRING)` | `load_date DATE` + `PARTITION BY load_date` | 27 sqoop mirrors |
| `PARTITIONED BY (extract_ts STRING)` | `extract_date DATE` + `PARTITION BY extract_date` | 8 delta feeds |
| `PARTITIONED BY (client_code STRING, feed_date STRING)` | `feed_date DATE` + `PARTITION BY feed_date` + `CLUSTER BY client_code` | 10 file feeds |
| `PARTITIONED BY (load_date STRING, site_code STRING)` | `load_date DATE` + `PARTITION BY load_date` + `CLUSTER BY site_code` | stg_wfm_schedule |
| `PARTITIONED BY (snapshot_date STRING)` | `snapshot_date DATE` + `PARTITION BY snapshot_date` | 6 ODS cleanse + ods_rate_card |
| `PARTITIONED BY (event_date STRING)` | `event_date DATE` + `PARTITION BY event_date` | 6 ODS cleanse + 2 delta-merge |
| `PARTITIONED BY (call_date STRING)` | `call_date DATE` + `PARTITION BY call_date` | ods_call |
| `PARTITIONED BY (sched_date STRING)` | `sched_date DATE` + `PARTITION BY sched_date` | ods_schedule |
| `PARTITIONED BY (work_month STRING)` | `work_month DATE` + `PARTITION BY work_month` (first-of-month: `'2024-01'` → `DATE '2024-01-01'`) | ods_timesheet |
| `PARTITIONED BY (period_month STRING)` | `period_month DATE` + `PARTITION BY period_month` (first-of-month) | ods_payroll_adjustment, ods_sla_credit, fact_billing_line, agg_program_monthly, agg_csat_rollup_monthly, agg_billing_monthly |
| `PARTITIONED BY (swap_month STRING)` | `swap_month DATE` + `PARTITION BY swap_month` (first-of-month) | ods_shift_swap |
| `PARTITIONED BY (event_month STRING)` | `event_month DATE` + `PARTITION BY event_month` (first-of-month) | ods_attrition_event |
| `PARTITIONED BY (eff_from_year INT)` | `eff_from_year INT64` + `PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2026, 1))` | 3 SCD-2 tables |
| `PARTITIONED BY (date_key INT)` | `date_key INT64` + `PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 10000))` | 12 DM facts/aggs |
| `PARTITIONED BY (date_key INT, channel STRING)` | `PARTITION BY RANGE_BUCKET(date_key, ...)` + `CLUSTER BY channel, agent_sk, client_sk` | fact_interaction |
| `PARTITIONED BY (week_start_key INT)` | `week_start_key INT64` + `PARTITION BY RANGE_BUCKET(week_start_key, GENERATE_ARRAY(20200101, 20260101, 10000))` | agg_agent_weekly |
| No partition (ACID / dimensions) | Unpartitioned | 4 ACID + 9 dimensions + dim_date |

### Multi-Column Partition → Single Partition + Clustering

BigQuery supports only one partition column per table. Multi-column Hive
partitions are handled by:
- Keeping the **date/integer** column as the partition key.
- Demoting the **string** column to a regular column + `CLUSTER BY` key.

| Table | Hive Partitions | BQ Partition | BQ Clustering |
|---|---|---|---|
| 10 file feeds | `client_code, feed_date` | `PARTITION BY feed_date` (DATE) | `CLUSTER BY client_code` |
| stg_wfm_schedule | `load_date, site_code` | `PARTITION BY load_date` (DATE) | `CLUSTER BY site_code` |
| fact_interaction | `date_key, channel` | `PARTITION BY RANGE_BUCKET(date_key, ...)` | `CLUSTER BY channel, agent_sk, client_sk` |

### Bucketing → Clustering

| Source | Hive CLUSTERED BY | BigQuery CLUSTER BY |
|---|---|---|
| `stg_tel_call` | `call_id INTO 16 BUCKETS` | `CLUSTER BY call_id` |
| `ods_client_acid` | `client_id INTO 4 BUCKETS` | `CLUSTER BY client_id` |
| `ods_agent_acid` | `agent_id INTO 8 BUCKETS` | `CLUSTER BY agent_id` |
| `ods_ticket_acid` | `ticket_id INTO 8 BUCKETS` | `CLUSTER BY ticket_id` |
| `ods_invoice_acid` | `invoice_id INTO 4 BUCKETS` | `CLUSTER BY invoice_id` |
| `fact_interaction` | `agent_sk INTO 16 BUCKETS` | Included in `CLUSTER BY channel, agent_sk, client_sk` |

---

## Epoch Encoding Policy

Full matrix in `docs/EPOCH-POLICY.md`. Below is the complete column inventory
organized by source family and encoding.

### Staging Layer: Epochs remain as INT64

All epoch columns stay as `INT64` in staging with `OPTIONS(description = ...)`
annotations documenting the encoding. There are **68 commented epoch columns**
across 3 encodings.

#### Epoch SECONDS — 34 columns

Staging INT64, ODS/DM → `TIMESTAMP` via `TIMESTAMP_SECONDS(x)`.

| Source Family | Table | Columns |
|---|---|---|
| **CRM (Oracle)** | stg_crm_client | `created_ts`, `updated_ts` |
| | stg_crm_client_contact | `created_ts` |
| | stg_crm_program | `go_live_ts`, `updated_ts` |
| | stg_crm_sla_target | `effective_ts` |
| **HR (SQL Server)** | stg_hr_agent | `hire_ts`, `term_ts` |
| | stg_hr_org_unit | `created_ts` |
| | stg_hr_employment_event | `event_ts` |
| | stg_hr_skill | `created_ts` |
| | stg_hr_agent_skill | `effective_ts`, `expiry_ts` |
| **WFM (MySQL)** | stg_wfm_shift | `created_epoch` |
| | stg_wfm_schedule | `start_epoch`, `end_epoch` |
| | stg_wfm_adherence_event | `start_epoch`, `end_epoch` |
| | stg_wfm_forecast | `interval_start_epoch` |
| | stg_wfm_timeoff_request | `request_epoch` |
| **Telephony (Oracle)** | stg_tel_call | `start_epoch`, `answer_epoch`, `end_epoch` |
| | stg_tel_call_segment | `start_epoch`, `end_epoch` |
| | stg_tel_queue | `created_epoch` |
| | stg_tel_agent_state_event | `start_epoch`, `end_epoch` |
| | stg_tel_disposition_code | `created_epoch` |
| **Finance** | stg_fin_rate_card | `effective_ts`, `expiry_ts` |
| **Delta feeds** | stg_tel_callback_request_delta | `requested_epoch`, `scheduled_epoch` |
| | stg_hr_attrition_event_delta | `notice_epoch` |

#### Epoch MILLISECONDS — 28 columns

Staging INT64, ODS/DM → `TIMESTAMP` via `TIMESTAMP_MILLIS(x)`.

| Source Family | Table | Columns |
|---|---|---|
| **Ticketing (Postgres)** | stg_tkt_ticket | `created_ms`, `updated_ms` |
| | stg_tkt_ticket_event | `event_ms` |
| | stg_tkt_category | `created_ms` |
| **Finance** | stg_fin_invoice_line | `created_ms` |
| **Delta feeds (all 8)** | stg_fin_timesheet_delta | `change_ms` |
| | stg_fin_payroll_adj_delta | `change_ms` |
| | stg_crm_sla_credit_delta | `change_ms` |
| | stg_tel_callback_request_delta | `change_ms` |
| | stg_wfm_shift_swap_delta | `change_ms` |
| | stg_tkt_worklog_delta | `log_ms`, `change_ms` |
| | stg_hr_attrition_event_delta | `change_ms` |
| | stg_fin_rate_card_change_delta | `change_ms` |
| **File feeds (all 10)** | stg_file_interaction_export | `start_ms`, `end_ms` |
| | stg_file_survey_csat | `survey_ms` |
| | stg_file_qa_forms | `evaluated_ms` |
| | stg_file_ivr_logs | `event_ms` |
| | stg_file_chat_transcripts | `started_ms`, `ended_ms` |
| | stg_file_roster | `as_of_ms` |
| | stg_file_telco_invoice | `billed_ms` |
| | stg_file_dialer_result | `attempt_ms` |
| | stg_file_email_interaction | `received_ms`, `first_reply_ms`, `resolved_ms` |
| | stg_file_speech_analytics | `analyzed_ms` |

#### Oracle String YYYYMMDDHH24MISS — 4 columns

Staging STRING, ODS/DM → `TIMESTAMP` via `PARSE_TIMESTAMP('%Y%m%d%H%M%S', x)`.

| Table | Columns |
|---|---|
| stg_crm_contract | `start_dt`, `end_dt`, `signed_dt` |
| stg_crm_contract_line | `effective_dt` |

#### LIE Columns — 2 columns

Column names say "seconds" but values are **milliseconds**.
Staging INT64, ODS/DM → `TIMESTAMP` via `TIMESTAMP_MILLIS(x)`.

| Table | Columns | Description |
|---|---|---|
| stg_fin_invoice | `issued_ts_sec`, `due_ts_sec` | `'WARNING: column name says seconds but VALUES ARE MILLISECONDS. All consumers divide by 1000. See EPOCH-POLICY.md.'` |

### ODS/DM Layers: All epoch-derived columns are TIMESTAMP

The cleanse layer casts all epoch integers/strings to `TIMESTAMP`:
- Epoch seconds → `TIMESTAMP_SECONDS(x)`
- Epoch milliseconds → `TIMESTAMP_MILLIS(x)`
- Oracle strings → `PARSE_TIMESTAMP('%Y%m%d%H%M%S', x)`
- LIE columns → `TIMESTAMP_MILLIS(x)` (the /1000 is only in views that compare raw staging)

---

## Complex Types (AC #8)

| Table | Column | Hive Type | BigQuery Type |
|---|---|---|---|
| `stg_file_qa_forms` | `sections` | `ARRAY<STRUCT<section_code:STRING,max_points:INT,scored_points:INT>>` | `ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>` |
| `stg_file_chat_transcripts` | `messages` | `ARRAY<STRUCT<sender:STRING,ts_ms:BIGINT,text:STRING>>` | `ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>` |
| `stg_file_chat_transcripts` | `metadata` | `MAP<STRING,STRING>` | `JSON` — query keys with `JSON_VALUE(metadata, '$.key_name')` |
| `stg_file_speech_analytics` | `keywords` | `ARRAY<STRING>` | `ARRAY<STRING>` (REPEATED STRING) |

Sub-field types are converted recursively: Hive `INT` → BigQuery `INT64`,
Hive `BIGINT` → BigQuery `INT64`, Hive `STRING` → BigQuery `STRING`.

---

## ACID Table Transformation (AC #3)

The 4 Hive ACID tables (`ods_client_acid`, `ods_agent_acid`, `ods_ticket_acid`,
`ods_invoice_acid`) are converted to native BigQuery managed tables:

- **Dropped**: `STORED AS ORC`, `transactional=true`, `orc.compress`, bucket count.
- **Preserved**: `CLUSTERED BY <pk>` → `CLUSTER BY <pk>`.
- **No partitioning** (small dimension-like tables used as MERGE targets).
- **No NOT NULL** constraints — all columns nullable for MERGE compatibility.

---

## SCD-2 Surrogate Key Generation (AC #5)

The 3 SCD-2 tables use STRING surrogate keys generated via `TO_HEX(MD5(...))`:

| Table | Key Column | Generation Expression |
|---|---|---|
| `ods_agent_scd2` | `agent_history_id` | `TO_HEX(MD5(CONCAT(CAST(agent_id AS STRING), '\|', CAST(eff_from_ts AS STRING))))` |
| `ods_agent_skill_scd2` | `agent_skill_history_id` | `TO_HEX(MD5(CONCAT(CAST(agent_id AS STRING), '\|', CAST(skill_id AS STRING), '\|', CAST(eff_from_ts AS STRING))))` |
| `ods_agent_assignment_scd2` | `assignment_history_id` | `TO_HEX(MD5(CONCAT(CAST(agent_id AS STRING), '\|', CAST(program_id AS STRING), '\|', CAST(eff_from_ts AS STRING))))` |

Each column's description documents the exact generation method.

---

## Format-Specific Table Provenance (AC #7)

All staging tables are created as BigQuery-native managed tables (not external).
Table-level `OPTIONS(description = ...)` documents the original Hive format:

| Original Format | Tables | Description |
|---|---|---|
| TEXTFILE pipe-delimited | 8 delta feeds | `'Source: Hive TEXTFILE pipe-delimited — loaded as CSV with pipe delimiter'` |
| TEXTFILE CSV | 4 file feeds (interaction_export, survey_csat, roster, email_interaction) | `'Source: Hive TEXTFILE CSV — loaded as CSV'` |
| JsonSerDe | 3 file feeds (qa_forms, chat_transcripts, speech_analytics) | `'Source: Hive JsonSerDe — loaded as NEWLINE_DELIMITED_JSON'` |
| RegexSerDe | stg_file_ivr_logs | `'Source: Hive RegexSerDe — pre-processed to structured format before BQ load'` |
| SequenceFile | stg_file_telco_invoice | `'Source: Hive SequenceFile — converted to Parquet/JSON for BQ load'` |
| RCFile | stg_file_dialer_result | `'Source: Hive RCFile — converted to Parquet/JSON for BQ load'` |
| PARQUET | 27 sqoop mirrors + all ODS/DM | Native BigQuery managed tables (no format annotation needed) |

---

## View SQL Dialect Translation

The 15 DM views translate Hive/Impala SQL to BigQuery Standard SQL.
See `dm/VIEW_AUDIT.md` for the detailed per-view audit report.

| Hive/Impala Syntax | BigQuery Equivalent | Views |
|---|---|---|
| `NDV(expr)` | `APPROX_COUNT_DISTINCT(expr)` | vw_active_agents_ndv |
| `GROUPING__ID` | `GROUPING(col1) * 2 + GROUPING(col2)` | vw_csat_rollup |
| `GROUP BY ... WITH ROLLUP` | `GROUP BY ROLLUP(...)` | vw_csat_rollup |
| `expr RLIKE 'pattern'` | `REGEXP_CONTAINS(expr, r'pattern')` | vw_call_driver_regex |
| `regexp_extract(str, pat, grp)` | `REGEXP_EXTRACT(str, r'pat')` | vw_call_driver_regex |
| `regexp_extract(...) <> ''` | `REGEXP_EXTRACT(...) IS NOT NULL` | vw_call_driver_regex |
| `unix_timestamp(ts)` | `UNIX_SECONDS(ts)` | vw_repeat_contact_window, vw_billing_reconciliation |
| `from_unixtime(epoch)` | `TIMESTAMP_SECONDS(epoch)` | vw_billing_reconciliation |
| `date_add(ts, N)` | `TIMESTAMP_ADD(ts, INTERVAL N DAY)` | vw_first_contact_resolution |
| `from_unixtime(unix_timestamp(str, fmt1), fmt2)` | `PARSE_DATE('%Y%m%d', CAST(... AS STRING))` | vw_shrinkage_analysis |
| `CAST(x AS BIGINT)` | `CAST(x AS INT64)` | vw_billing_reconciliation |
| `WITH RECURSIVE org_tree (cols) AS` | `WITH RECURSIVE org_tree AS` | vw_org_hierarchy |
| HQL `\\\\[` double-backslash escapes | Raw string `r'\['` single-backslash | vw_call_driver_regex |

---

## Execution Order

The `run-all-ddl.sh` script deploys 116 DDL executions in dependency order:

1. **Phase 1** — `00-create-datasets.sql` (3 datasets: staging, ods, dm)
2. **Phase 2** — `staging/*.sql` (45 tables, no dependencies)
3. **Phase 3** — `ods/*.sql` (30 tables, no inter-DDL dependencies)
4. **Phase 4** — `dm/*.sql` excluding `vw_*` (25 tables, no inter-DDL dependencies)
5. **Phase 5** — `dm/vw_*.sql` (15 views, depend on tables in all 3 datasets)

Views must run last because they reference tables across staging, ods, and dm
datasets (e.g., `vw_queue_sla_attainment` reads `staging.stg_crm_sla_target`).

The script prints coverage lines per AC #1 and #12:
- `applied X/100 tables`
- `applied X/15 views`

Any object that fails to create is a **HARD FAIL** naming the table/view and
the BigQuery error message.

---

## Validation

11 SQL scripts in `validation/` verify acceptance criteria against the live
BigQuery INFORMATION_SCHEMA after deployment:

| Script | AC | What It Checks |
|---|---|---|
| `check_column_counts.sql` | #1 | Column counts for all 100 tables |
| `check_epoch_types.sql` | #2 | Epoch column types + descriptions |
| `check_acid_tables.sql` | #3 | ACID tables native/nullable/no ORC |
| `check_identifiers.sql` | #4 | Identifier legality |
| `check_scd2_keys.sql` | #5 | SCD-2 surrogate keys |
| `check_decimal_precision.sql` | #6 | DECIMAL precision/scale |
| `check_format_tables.sql` | #7 | Format provenance |
| `check_complex_types.sql` | #8 | Complex types recursive |
| `check_nullability.sql` | #9 | No NULLABLE→REQUIRED |
| `check_partition_types.sql` | #10 | No STRING partitions |
| `check_comment_preservation.sql` | #11 | 68 Hive COMMENTs preserved |

Run all checks: `./validation/validate_all.sh --project my-gcp-project`
