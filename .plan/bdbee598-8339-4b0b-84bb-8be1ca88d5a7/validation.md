# Validation

## Validation Strategy: `staging.stg_crm_contract` DDL Conversion

### Acceptance Criteria → Test Mapping

Each AC maps to specific automated assertions in the validation script (`validation/stg_crm_contract_validate.mjs`):

---

**AC#1 — DDL applies cleanly, managed table, all 11 columns present**
- Execute `CREATE TABLE` DDL against a scratch BigQuery dataset
- Call `table.getMetadata()` and assert:
  - No error thrown (zero-error creation)
  - `metadata.type === 'TABLE'` (managed, not EXTERNAL or VIEW)
  - `metadata.schema.fields.length === 11` (10 source columns + inlined `load_date`)
- **Verdict**: Script exit code (0 = pass, 1 = fail)

---

**AC#2 — Column type fidelity**
- From `getMetadata().schema.fields`, assert each column's type:

  | Column | Expected BQ Type |
  |---|---|
  | `contract_id` | `INT64` |
  | `client_id` | `INT64` |
  | `program_id` | `INT64` |
  | `contract_no` | `STRING` |
  | `start_dt` | `STRING` |
  | `end_dt` | `STRING` |
  | `billing_model` | `STRING` |
  | `currency` | `STRING` |
  | `signed_dt` | `STRING` |
  | `status` | `STRING` |
  | `load_date` | `DATE` |

- Specifically assert `start_dt`, `end_dt`, `signed_dt` are **STRING** (not DATETIME/TIMESTAMP) — this is the "no implicit DATETIME cast" requirement
- No columns dropped, no columns renamed

---

**AC#3 — No Hive storage clauses in output**
- Parse the DDL file text and assert:
  - Does NOT contain `EXTERNAL`
  - Does NOT contain `STORED AS`
  - Does NOT contain `PARQUET` (as a storage directive)
  - Does NOT contain `LOCATION`
  - Does NOT contain `hdfs://`
  - Does NOT contain `TBLPROPERTIES`
  - Does NOT contain `SNAPPY`
- From `getMetadata()`, assert `metadata.type === 'TABLE'` (not `EXTERNAL`)

---

**AC#4 — Partition strategy verified from metadata**
- From `getMetadata()`, assert:
  - `metadata.timePartitioning` is present (or `metadata.rangePartitioning` — but DATE partitioning produces `timePartitioning` with `type: 'DAY'` and `field: 'load_date'`)
  - `timePartitioning.field === 'load_date'`
  - `timePartitioning.type === 'DAY'`
- Assert `load_date` appears in `schema.fields` (inlined, not just a partition pseudo-column)
- Assert total field count = 11 (10 source + 1 inlined partition)

---

**AC#5 — Legal BigQuery identifiers**
- For the table name `stg_crm_contract` and all 11 column names, assert:
  - Matches regex `^[a-zA-Z_][a-zA-Z0-9_]{0,1023}$`
  - Not in the BigQuery reserved-word list (check against `ARRAY`, `STRUCT`, `SELECT`, `FROM`, `TABLE`, `GROUP`, `ORDER`, `PARTITION`, etc.)
  - No case-fold collisions (no two column names that differ only by case)

---

**AC#6 — Cross-engine edge-value round-trip**
- **Setup**: Create a scratch source table on Impala (via the Impala `nosasl` handle) using the source `.hql` DDL (`CREATE TABLE IF NOT EXISTS`). Create the scratch target table on BigQuery using the converted DDL.
- **Seed canonical edge values into BOTH tables**:

  | Edge case | Column(s) | Value |
  |---|---|---|
  | BIGINT max | `contract_id` | `9223372036854775807` |
  | BIGINT min | `contract_id` | `-9223372036854775808` |
  | Unicode + control chars | `contract_no` | `'café — 日本語 — 🎉'` + TAB (`\t`) + NEWLINE (`\n`) |
  | NULL | `contract_no` | `NULL` |
  | Empty string | `contract_no` | `''` |
  | Oracle string date | `start_dt` | `'20230615143022'` |
  | NULL date | `end_dt` | `NULL` |

- **Read back from both engines** and assert:
  - BIGINT boundary values survive round-trip in both INT64 (BQ) and BIGINT (Impala)
  - Unicode string including emoji, CJK, TAB, NEWLINE is byte-identical
  - NULL row and empty-string (`''`) row remain **distinct** (NULL ≠ empty)
  - Oracle string-date value preserved character-for-character as STRING
- **Verdict**: Script exit code; report "state coverage probed X of Y" per AC wording

### Edge Cases & Error Handling

- **BigQuery reserved words**: `status` is NOT a BigQuery reserved word (it's unreserved), so no backtick-escaping needed. Validated by checking against the official BQ reserved word list.
- **Column description round-trip**: The three Oracle date column descriptions (`Oracle string YYYYMMDDHH24MISS (legacy)`) should survive as BigQuery column `OPTIONS(description=...)`. Validated by reading back from metadata.
- **Empty table creation**: The DDL should work even when the target dataset has no data — `CREATE TABLE` should succeed with zero rows.
