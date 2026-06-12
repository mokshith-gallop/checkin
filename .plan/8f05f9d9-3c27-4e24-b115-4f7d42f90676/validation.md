# Validation

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
