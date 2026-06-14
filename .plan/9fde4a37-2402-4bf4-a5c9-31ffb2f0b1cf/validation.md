# Validation

## Validation: DDL Correctness & Acceptance Criteria Coverage

### 1. Syntactic Validation — Zero-Error DDL Application (AC #1)
Every generated `.sql` file must be executable via `bq query --nouse_legacy_sql` against a scratch dataset with zero errors. Validation approach:

- **Automated dry-run script** (`validation/validate_ddl.sh`): Iterates all 115 DDL files, runs each against a temporary BigQuery dataset (`_ddl_validation_scratch`), captures exit codes and error messages, then drops the dataset.
- **Column count reconciliation**: After applying all DDL, query `INFORMATION_SCHEMA.COLUMNS` for each table and compare column counts against the source counts in `manifests/tables.yaml`. The expected count = data columns + inlined partition columns. Generate a report: `validation/column_count_report.csv`.
- **Pass criteria**: 100 tables created, 15 views created, 0 errors, all column counts match.

### 2. Epoch Encoding Validation (AC #2)
Verify that the DDL correctly types epoch columns per the EPOCH-POLICY.md matrix:

- **Staging layer check**: Query `INFORMATION_SCHEMA.COLUMNS` for all columns tagged `epoch_sec`, `epoch_ms`, `ora_str`, or `lie_ms` in `tables.yaml`. Assert all are `INT64` (not TIMESTAMP) in staging.
- **ODS/DM layer check**: Assert all epoch-derived columns are `TIMESTAMP` (not INT64 or STRING).
- **Lie column description check**: Assert `stg_fin_invoice.issued_ts_sec` and `stg_fin_invoice.due_ts_sec` have column descriptions containing the word "milliseconds" or "MILLIS" — proving the trap is documented.
- **Validation SQL**: `validation/check_epoch_types.sql` — a single BigQuery script that runs all 4 assertions and outputs PASS/FAIL per check.

### 3. Complex Type Validation (AC #3)
Verify ARRAY, STRUCT, and JSON columns via `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`:

- `stg_file_qa_forms.sections`: Assert `data_type` = `ARRAY<STRUCT<section_code STRING, max_points INT64, scored_points INT64>>` with 3 sub-fields in COLUMN_FIELD_PATHS.
- `stg_file_chat_transcripts.messages`: Assert `data_type` = `ARRAY<STRUCT<sender STRING, ts_ms INT64, text STRING>>` with 3 sub-fields.
- `stg_file_chat_transcripts.metadata`: Assert `data_type` = `JSON`.
- `stg_file_speech_analytics.keywords`: Assert `data_type` = `ARRAY<STRING>` (REPEATED STRING).
- **Validation SQL**: `validation/check_complex_types.sql`

### 4. ACID Table Validation (AC #4)
For the 4 ACID tables (`ods_client_acid`, `ods_agent_acid`, `ods_ticket_acid`, `ods_invoice_acid`):

- Assert each exists in `INFORMATION_SCHEMA.TABLES` as type `BASE TABLE` (not `EXTERNAL`).
- Assert no column has `is_nullable = 'NO'` (all nullable → MERGE-compatible).
- Assert no table description contains 'ORC' or 'transactional'.
- **Validation SQL**: `validation/check_acid_tables.sql`

### 5. SCD-2 Surrogate Key Validation (AC #5)
For the 3 SCD-2 tables:

- Assert `agent_history_id`, `agent_skill_history_id`, `assignment_history_id` are `STRING` type.
- Assert each column's description contains `TO_HEX(MD5(` — proving the generation method is documented.
- **Validation SQL**: `validation/check_scd2_keys.sql`

### 6. Format Provenance Validation (AC #6)
For the 14 format-specific staging tables (8 pipe-delimited TEXTFILE, 3 RegexSerDe/SequenceFile/RCFile, 3 JsonSerDe):

- Assert all are `BASE TABLE` in `INFORMATION_SCHEMA.TABLES` (not external).
- Assert no table description contains 'SerDe', 'TEXTFILE', 'SEQUENCEFILE', or 'RCFILE' as a property — only as historical documentation.
- Assert table descriptions DO contain provenance text (e.g., 'Source: Hive RegexSerDe').
- **Validation SQL**: `validation/check_format_tables.sql`

### 7. DECIMAL Precision Validation (AC #7)
For all DECIMAL columns across all layers:

- Query `INFORMATION_SCHEMA.COLUMNS` where `data_type LIKE 'NUMERIC%'`.
- Assert each maps to `NUMERIC` (not `BIGNUMERIC`) since all 12 source precision/scale pairs (including the largest at DECIMAL(14,2)) fit within NUMERIC(38,9).
- Assert no column is widened beyond the source precision.
- Cross-reference the 12 distinct precision/scale pairs: `DECIMAL(14,2)`, `DECIMAL(12,4)`, `DECIMAL(12,2)`, `DECIMAL(10,4)`, `DECIMAL(8,2)`, `DECIMAL(7,2)`, `DECIMAL(5,2)`.
- **Validation SQL**: `validation/check_decimal_precision.sql`

### 8. Cross-Cutting Validation
- **Manifest completeness**: A Python script (`validation/check_manifest_coverage.py`) parses `manifests/tables.yaml` and asserts every table/view has a corresponding `.sql` file in `bigquery/ddl/`.
- **View dependency order**: Assert all tables referenced by each view exist before the view is created. The `run-all-ddl.sh` script must execute views last.
- **Naming convention**: Assert all table/view names in BigQuery match the source names exactly (case-sensitive comparison against `tables.yaml`).

### Edge Cases & Error Handling
- **NULL partition values**: BigQuery handles NULL in DATE partitions as `__NULL__` partition — no special DDL needed.
- **Empty ARRAY/STRUCT**: BigQuery allows empty arrays natively — no default value needed.
- **JSON column with no schema enforcement**: The `metadata` JSON column accepts any valid JSON — this is intentional (MAP semantics).
- **NUMERIC precision**: If a future column exceeds NUMERIC(38,9), the validation will flag it for BIGNUMERIC upgrade — but none currently do.
