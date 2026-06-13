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
   compatibility (AC #4).

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
| `DECIMAL(p,s)` | `NUMERIC(p,s)` | All 7 precision/scale pairs fit NUMERIC(38,9) |
| `ARRAY<STRUCT<...>>` | `ARRAY<STRUCT<...>>` | Native BigQuery support |
| `ARRAY<STRING>` | `ARRAY<STRING>` | REPEATED STRING |
| `MAP<STRING,STRING>` | `JSON` | Query keys via `JSON_VALUE(col, '$.key')` |

---

## DECIMAL Precision/Scale Inventory

All source DECIMAL columns map to NUMERIC (never BIGNUMERIC). The 7 distinct
precision/scale pairs are:

| Precision/Scale | Example Columns |
|---|---|
| `NUMERIC(14,2)` | `total_amount`, `line_amount`, `billed_amount`, `net_revenue` |
| `NUMERIC(12,4)` | `unit_rate`, `rate`, `old_rate`, `new_rate` |
| `NUMERIC(12,2)` | `min_commit`, `amount`, `credit_amount`, `charge_amount`, `qty` |
| `NUMERIC(10,4)` | `target_value` |
| `NUMERIC(8,2)` | `required_fte`, `avg_speed_answer_sec`, `avg_handle_sec`, `avg_handle_seconds` |
| `NUMERIC(7,2)` | `volume_variance_pct` |
| `NUMERIC(5,2)` | `penalty_pct`, `overall_pct`, `adherence_pct`, `occupancy_pct`, `sl_pct`, `pct_promoters`, `pct_detractors` |

None exceed NUMERIC(38,9), so no BIGNUMERIC is used anywhere.

---

## Partitioning Translation

| Source Pattern | BigQuery Translation | Tables |
|---|---|---|
| `PARTITIONED BY (load_date STRING)` | `load_date DATE` + `PARTITION BY load_date` | 27 sqoop mirrors |
| `PARTITIONED BY (extract_ts STRING)` | `extract_date DATE` + `PARTITION BY extract_date` | 8 delta feeds |
| `PARTITIONED BY (client_code STRING, feed_date STRING)` | `feed_date DATE` + `PARTITION BY feed_date` + `CLUSTER BY client_code` | 10 file feeds |
| `PARTITIONED BY (load_date STRING, site_code STRING)` | `PARTITION BY load_date` + `CLUSTER BY site_code` | stg_wfm_schedule |
| `PARTITIONED BY (snapshot_date STRING)` | `snapshot_date DATE` + `PARTITION BY snapshot_date` | 6 ODS cleanse + ods_rate_card |
| `PARTITIONED BY (event_date STRING)` | `event_date DATE` + `PARTITION BY event_date` | 8 ODS cleanse + 2 delta-merge |
| `PARTITIONED BY (call_date STRING)` | `call_date DATE` + `PARTITION BY call_date` | ods_call |
| `PARTITIONED BY (sched_date STRING)` | `sched_date DATE` + `PARTITION BY sched_date` | ods_schedule |
| `PARTITIONED BY (work_month/period_month/swap_month/event_month STRING)` | `<col> DATE` + `PARTITION BY <col>` (first-of-month convention) | 5 ODS delta-merge, 4 DM aggs/facts |
| `PARTITIONED BY (eff_from_year INT)` | `PARTITION BY RANGE_BUCKET(eff_from_year, GENERATE_ARRAY(2020, 2026, 1))` | 3 SCD-2 |
| `PARTITIONED BY (date_key INT)` | `PARTITION BY RANGE_BUCKET(date_key, GENERATE_ARRAY(20200101, 20260101, 1))` | 12 DM facts/aggs |
| `PARTITIONED BY (date_key INT, channel STRING)` | `PARTITION BY RANGE_BUCKET(date_key, ...)` + `CLUSTER BY channel, agent_sk, client_sk` | fact_interaction |
| `PARTITIONED BY (week_start_key INT)` | `PARTITION BY RANGE_BUCKET(week_start_key, GENERATE_ARRAY(20200101, 20260101, 1))` | agg_agent_weekly |
| No partition (ACID / dimensions) | Unpartitioned | 4 ACID + 9 dimensions |

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

Full matrix in `docs/EPOCH-POLICY.md`. Summary of treatment by layer:

### Staging Layer: Epochs remain as INT64

All epoch columns stay as `INT64` in staging with `OPTIONS(description = ...)`
annotations documenting the encoding:

| Encoding | Description Tag | Source Families |
|---|---|---|
| Epoch seconds | `'epoch SECONDS (legacy)'` | Telephony, WFM, HR, CRM (most), Finance (rate_card) |
| Epoch milliseconds | `'epoch MILLISECONDS (legacy)'` | Ticketing, all delta feeds (change_ms), all file feeds (*_ms), Finance (invoice_line) |
| Oracle string | `'Oracle string YYYYMMDDHH24MISS (legacy)'` | CRM contract tables (start_dt, end_dt, signed_dt, effective_dt) |
| **LIE columns** | `'WARNING: column name says seconds but VALUES ARE MILLISECONDS...'` | `stg_fin_invoice.issued_ts_sec`, `stg_fin_invoice.due_ts_sec` |

### ODS/DM Layers: All epoch-derived columns are TIMESTAMP

The cleanse layer casts all epoch integers/strings to `TIMESTAMP`:
- Epoch seconds → `TIMESTAMP_SECONDS(x)`
- Epoch milliseconds → `TIMESTAMP_MILLIS(x)`
- Oracle strings → `PARSE_TIMESTAMP('%Y%m%d%H%M%S', x)`
- LIE columns → `TIMESTAMP_MILLIS(x)` (divide by 1000 despite the name)

---

## Complex Types (AC #3)

| Table | Column | Hive Type | BigQuery Type |
|---|---|---|---|
| `stg_file_qa_forms` | `sections` | `ARRAY<STRUCT<section_code:STRING,max_points:INT,scored_points:INT>>` | `ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>` |
| `stg_file_chat_transcripts` | `messages` | `ARRAY<STRUCT<sender:STRING,ts_ms:BIGINT,text:STRING>>` | `ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>` |
| `stg_file_chat_transcripts` | `metadata` | `MAP<STRING,STRING>` | `JSON` — query keys with `JSON_VALUE(metadata, '$.key_name')` |
| `stg_file_speech_analytics` | `keywords` | `ARRAY<STRING>` | `ARRAY<STRING>` (REPEATED STRING) |

---

## ACID Table Transformation (AC #4)

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

## Format-Specific Table Provenance (AC #6)

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

The 15 DM views translate Hive/Impala SQL to BigQuery Standard SQL:

| Hive/Impala Syntax | BigQuery Equivalent | Views |
|---|---|---|
| `NDV(expr)` | `APPROX_COUNT_DISTINCT(expr)` | vw_active_agents_ndv |
| `GROUPING__ID` | `GROUPING(col1) * 2 + GROUPING(col2)` | vw_csat_rollup |
| `GROUP BY ... WITH ROLLUP` | `GROUP BY ROLLUP(...)` | vw_csat_rollup |
| `expr RLIKE 'pattern'` | `REGEXP_CONTAINS(expr, r'pattern')` | vw_call_driver_regex |
| `regexp_extract(str, pat, grp)` | `REGEXP_EXTRACT(str, r'pat')` | vw_call_driver_regex |
| `unix_timestamp(ts)` | `UNIX_SECONDS(ts)` | vw_repeat_contact_window, vw_billing_reconciliation |
| `from_unixtime(epoch)` | `TIMESTAMP_SECONDS(epoch)` | vw_billing_reconciliation |
| `date_add(ts, N)` | `TIMESTAMP_ADD(ts, INTERVAL N DAY)` | vw_first_contact_resolution |
| `from_unixtime(unix_timestamp(str, fmt1), fmt2)` | `PARSE_DATE('%Y%m%d', CAST(... AS STRING))` | vw_shrinkage_analysis |
| `CAST(x AS BIGINT)` | `CAST(x AS INT64)` | vw_billing_reconciliation |
| `WITH RECURSIVE` | `WITH RECURSIVE` (native support) | vw_org_hierarchy |

---

## Execution Order

The `run-all-ddl.sh` script ensures correct dependency order:

1. **Phase 1** — `00-create-datasets.sql` (3 datasets)
2. **Phase 2** — `staging/*.sql` (45 tables, no dependencies)
3. **Phase 3** — `ods/*.sql` (30 tables, no inter-DDL dependencies)
4. **Phase 4** — `dm/*.sql` excluding `vw_*` (25 tables, no inter-DDL dependencies)
5. **Phase 5** — `dm/vw_*.sql` (15 views, depend on tables in all 3 datasets)

Views must run last because they reference tables across staging, ods, and dm
datasets (e.g., `vw_queue_sla_attainment` reads `staging.stg_crm_sla_target`).
