# Implementation Approach

## Implementation Approach: `staging.stg_crm_contract` DDL Conversion

### What Gets Built
A single BigQuery DDL file (`bigquery/ddl/staging/stg_crm_contract.sql`) containing a `CREATE TABLE` statement for `staging.stg_crm_contract`, plus a Node.js validation script that:
1. Applies the DDL to a scratch BigQuery dataset
2. Reads back the landed schema via `table.getMetadata()`
3. Seeds edge-case rows into both a scratch Impala source table and the BigQuery target
4. Asserts column-for-column type fidelity and data round-trip correctness

### Key Technical Choices

1. **Managed table, no Hive storage clauses**: The BigQuery DDL is a plain `CREATE TABLE` — no `EXTERNAL`, `STORED AS PARQUET`, `LOCATION`, or `TBLPROPERTIES`. AC#3 requires the landed object to be a managed `TABLE`, verified via `getMetadata().

2. **`load_date` inlined as DATE + used as partition column**: The Hive `PARTITIONED BY (load_date STRING)` becomes a regular column declared inline with type `DATE`, and the table is partitioned via `PARTITION BY load_date`. This is the **only** type change from the source — chosen because BigQuery requires DATE/TIMESTAMP/DATETIME/INT64 for partitioning, and the downstream cleanse script (`10-cleanse-contract.sql`) already compares `load_date = run_date` where `run_date` is `DATE`.

3. **Column count**: Source has 10 declared columns + 1 partition column (`load_date`) = 11 total. BigQuery DDL declares all 11 inline. AC#4 expects `landed column COUNT == source count + the inlined partition column` — which is 10 + 1 = 11 columns.

4. **Oracle string-date columns stay STRING**: `start_dt`, `end_dt`, `signed_dt` remain `STRING` per AC#2. No implicit `DATETIME` or `TIMESTAMP` cast. The semantic parsing is the ODS layer's job (script `10-cleanse-contract.sql` handles it with `PARSE_TIMESTAMP`).

5. **Column descriptions preserved**: The source `COMMENT` annotations on the three Oracle string-date columns will be carried forward as BigQuery `OPTIONS(description=...)` on each column.

### File Location
`bigquery/ddl/staging/stg_crm_contract.sql` — following a `bigquery/ddl/{dataset}/{table}.sql` convention. This is the first staging DDL file in the destination; subsequent staging table stories will follow this pattern.

### Validation Script
A Node.js (`.mjs`) validation script at `validation/stg_crm_contract_validate.mjs` that:
- **AC#1**: Creates the table in a scratch dataset, reads back metadata, asserts 11 columns, zero errors, managed table type
- **AC#2**: Asserts type mapping: `contract_id/client_id/program_id` → INT64; `contract_no/billing_model/currency/status` → STRING; `start_dt/end_dt/signed_dt` → STRING; `load_date` → DATE
- **AC#3**: Asserts no EXTERNAL, PARQUET, HDFS, or SNAPPY references; object type is TABLE (not VIEW/EXTERNAL)
- **AC#4**: Asserts `load_date` is in the column list AND `timePartitioning` is present in metadata; column count = 11
- **AC#5**: Asserts all identifiers are legal BigQuery names (regex `^[a-zA-Z_][a-zA-Z0-9_]*$`, length ≤ 1024, not a reserved word)
- **AC#6**: Creates a parallel Impala source table, seeds identical edge values (BIGINT boundaries ±9223372036854775807/808, Unicode/control chars, NULL vs empty string), reads back from both, and compares

### Integration Points
- The DDL must be compatible with the existing `10-cleanse-contract.sql` which reads `staging.stg_crm_contract` with `WHERE s.load_date = run_date`
- The `staging` dataset must exist (created by infrastructure setup, not this story)
