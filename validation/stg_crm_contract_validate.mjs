// validation/stg_crm_contract_validate.mjs
// Validates the converted BigQuery DDL for staging.stg_crm_contract
// Covers AC#1–AC#5 (schema/metadata validation).
// AC#6 (cross-engine edge-value round-trip) is appended below.
//
// Usage:
//   set -a; source /workspace/.gallop/db.env; set +a
//   node validation/stg_crm_contract_validate.mjs

import { createRequire } from 'module';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');

// ── BigQuery client ─────────────────────────────────────────────────────────
const authClient = new OAuth2Client();
authClient.setCredentials({ access_token: process.env.CHECKIN_BQ_TOKEN });
const bq = new BigQuery({
  projectId: process.env.CHECKIN_BQ_PROJECT,
  authClient,
});
const BQ_DATASET = process.env.CHECKIN_BQ_DATASETS || 'test';
const BQ_TABLE   = 'stg_crm_contract';

// ── Paths ───────────────────────────────────────────────────────────────────
const __dirname = dirname(fileURLToPath(import.meta.url));
const DDL_PATH  = resolve(__dirname, '..', 'bigquery', 'ddl', 'staging', 'stg_crm_contract.sql');

// ── Test harness ────────────────────────────────────────────────────────────
let passed = 0;
let failed = 0;

function check(name, condition, detail) {
  if (condition) {
    console.log(`  ✓ ${name}`);
    passed++;
  } else {
    console.log(`  ✗ ${name}: ${detail}`);
    failed++;
  }
}

// ── BigQuery reserved words (Standard SQL) ──────────────────────────────────
// Official list from https://cloud.google.com/bigquery/docs/reference/standard-sql/lexical#reserved_keywords
const BQ_RESERVED_WORDS = new Set([
  'ALL', 'AND', 'ANY', 'ARRAY', 'AS', 'ASC', 'ASSERT_ROWS_MODIFIED', 'AT',
  'BETWEEN', 'BY', 'CASE', 'CAST', 'COLLATE', 'CONTAINS', 'CREATE', 'CROSS',
  'CUBE', 'CURRENT', 'DEFAULT', 'DEFINE', 'DESC', 'DISTINCT', 'ELSE', 'END',
  'ENUM', 'ESCAPE', 'EXCEPT', 'EXCLUDE', 'EXISTS', 'EXTRACT', 'FALSE', 'FETCH',
  'FOLLOWING', 'FOR', 'FROM', 'FULL', 'GROUP', 'GROUPING', 'GROUPS', 'HASH',
  'HAVING', 'IF', 'IGNORE', 'IN', 'INNER', 'INTERSECT', 'INTERVAL', 'INTO',
  'IS', 'JOIN', 'LATERAL', 'LEFT', 'LIKE', 'LIMIT', 'LOOKUP', 'MERGE', 'NATURAL',
  'NEW', 'NO', 'NOT', 'NULL', 'NULLS', 'OF', 'ON', 'OR', 'ORDER', 'OUTER',
  'OVER', 'PARTITION', 'PRECEDING', 'PROTO', 'RANGE', 'RECURSIVE', 'RESPECT',
  'RIGHT', 'ROLLUP', 'ROWS', 'SELECT', 'SET', 'SOME', 'STRUCT', 'TABLESAMPLE',
  'THEN', 'TO', 'TREAT', 'TRUE', 'UNBOUNDED', 'UNION', 'UNNEST', 'USING',
  'WHEN', 'WHERE', 'WINDOW', 'WITH', 'WITHIN',
]);

// ── Expected schema ─────────────────────────────────────────────────────────
// Note: BigQuery REST API returns 'INTEGER' for INT64 columns in getMetadata().
// Both names refer to the same underlying 64-bit signed integer type.
const EXPECTED_COLUMNS = [
  { name: 'contract_id',   type: 'INTEGER',  ddlType: 'INT64' },
  { name: 'client_id',     type: 'INTEGER',  ddlType: 'INT64' },
  { name: 'program_id',    type: 'INTEGER',  ddlType: 'INT64' },
  { name: 'contract_no',   type: 'STRING',   ddlType: 'STRING' },
  { name: 'start_dt',      type: 'STRING',   ddlType: 'STRING' },
  { name: 'end_dt',        type: 'STRING',   ddlType: 'STRING' },
  { name: 'billing_model', type: 'STRING',   ddlType: 'STRING' },
  { name: 'currency',      type: 'STRING',   ddlType: 'STRING' },
  { name: 'signed_dt',     type: 'STRING',   ddlType: 'STRING' },
  { name: 'status',        type: 'STRING',   ddlType: 'STRING' },
  { name: 'load_date',     type: 'DATE',     ddlType: 'DATE' },
];

// Columns that MUST remain STRING (not DATETIME/TIMESTAMP)
const MUST_BE_STRING = ['start_dt', 'end_dt', 'signed_dt'];

// ── Hive storage clause keywords that must NOT appear in DDL body ───────────
const HIVE_FORBIDDEN = [
  { pattern: /\bEXTERNAL\b/i,              label: 'EXTERNAL' },
  { pattern: /\bSTORED\s+AS\b/i,           label: 'STORED AS' },
  { pattern: /\bPARQUET\b/i,               label: 'PARQUET' },
  { pattern: /\bLOCATION\s+'/i,            label: 'LOCATION' },
  { pattern: /hdfs:\/\//i,                 label: 'hdfs://' },
  { pattern: /\bTBLPROPERTIES\b/i,         label: 'TBLPROPERTIES' },
  { pattern: /\bSNAPPY\b/i,                label: 'SNAPPY' },
];

// ── Identifier regex ────────────────────────────────────────────────────────
const IDENT_RE = /^[a-zA-Z_][a-zA-Z0-9_]{0,1023}$/;

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════
async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('VALIDATION: staging.stg_crm_contract DDL Conversion');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');

  // ── Read DDL ──────────────────────────────────────────────────────────
  let ddlRaw;
  try {
    ddlRaw = readFileSync(DDL_PATH, 'utf8');
    console.log(`  DDL file read: ${DDL_PATH} (${ddlRaw.length} bytes)`);
  } catch (err) {
    console.error(`  FATAL: cannot read DDL file at ${DDL_PATH}: ${err.message}`);
    process.exit(1);
  }

  // Strip comment lines from DDL to get the functional body
  const ddlBody = ddlRaw
    .split('\n')
    .filter(line => !line.trimStart().startsWith('--'))
    .join('\n');

  // Rewrite dataset: staging. → test. for the scratch dataset
  const ddlForScratch = ddlRaw.replace(
    /\bstaging\.stg_crm_contract\b/g,
    `${BQ_DATASET}.${BQ_TABLE}`
  );
  // Also replace CREATE TABLE IF NOT EXISTS with CREATE OR REPLACE TABLE
  // so re-runs work cleanly
  const ddlExec = ddlForScratch.replace(
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS/i,
    'CREATE OR REPLACE TABLE'
  );

  // ══════════════════════════════════════════════════════════════════════
  // AC#1 — DDL applies cleanly, managed table, all 11 columns present
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#1: DDL applies cleanly, managed table, 11 columns');
  console.log('  artifact: bigquery/ddl/staging/stg_crm_contract.sql');
  console.log('');

  let metadata;
  let fields;
  try {
    // Execute DDL
    await bq.query({ query: ddlExec });
    console.log(`  DDL executed successfully in dataset '${BQ_DATASET}'`);

    // Read back metadata
    const dataset = bq.dataset(BQ_DATASET);
    const table = dataset.table(BQ_TABLE);
    const [meta] = await table.getMetadata();
    metadata = meta;
    fields = metadata.schema?.fields || [];

    check('DDL executed without errors', true, '');
    check('table type is TABLE (managed)',
      metadata.type === 'TABLE',
      `got type '${metadata.type}'`);
    check('column count is 11',
      fields.length === 11,
      `got ${fields.length} columns: ${fields.map(f => f.name).join(', ')}`);
  } catch (err) {
    check('DDL executed without errors', false, err.message);
    check('table type is TABLE (managed)', false, 'DDL execution failed');
    check('column count is 11', false, 'DDL execution failed');
    console.log('');
    console.log(`  RESULT: FAIL — DDL execution error, cannot proceed`);
    console.log(`  ${passed} passed, ${failed} failed`);
    process.exit(1);
  }

  // ══════════════════════════════════════════════════════════════════════
  // AC#2 — Column type fidelity
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#2: Column type fidelity');
  console.log('');

  // Build a lookup from the landed schema
  const landedMap = new Map(fields.map(f => [f.name, f.type]));

  for (const expected of EXPECTED_COLUMNS) {
    const actual = landedMap.get(expected.name);
    check(`${expected.name} → ${expected.ddlType} (API: ${expected.type})`,
      actual === expected.type,
      `expected ${expected.type} (DDL: ${expected.ddlType}), got ${actual || '(missing)'}`);
  }

  // Specific assertion: Oracle string-date columns must NOT be DATETIME/TIMESTAMP
  for (const col of MUST_BE_STRING) {
    const actual = landedMap.get(col);
    check(`${col} is NOT DATETIME or TIMESTAMP`,
      actual !== 'DATETIME' && actual !== 'TIMESTAMP',
      `got ${actual} — implicit date cast detected`);
  }

  // No columns dropped or renamed
  const landedNames = new Set(fields.map(f => f.name));
  const expectedNames = new Set(EXPECTED_COLUMNS.map(c => c.name));
  const extraCols = [...landedNames].filter(n => !expectedNames.has(n));
  const missingCols = [...expectedNames].filter(n => !landedNames.has(n));
  check('no extra columns',
    extraCols.length === 0,
    `unexpected columns: ${extraCols.join(', ')}`);
  check('no missing columns',
    missingCols.length === 0,
    `missing columns: ${missingCols.join(', ')}`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#3 — No Hive storage clauses in output DDL
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#3: No Hive storage clauses in DDL body');
  console.log('');

  for (const { pattern, label } of HIVE_FORBIDDEN) {
    const found = pattern.test(ddlBody);
    check(`DDL body does not contain '${label}'`,
      !found,
      `found '${label}' in functional DDL body`);
  }

  // Metadata-level: type is TABLE (not EXTERNAL)
  check('metadata confirms managed TABLE (not EXTERNAL)',
    metadata.type === 'TABLE',
    `got type '${metadata.type}'`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#4 — Partition strategy verified from metadata
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#4: Partition strategy verified from metadata');
  console.log('');

  const tp = metadata.timePartitioning;
  check('timePartitioning is present',
    !!tp,
    'metadata.timePartitioning is missing');

  if (tp) {
    check('timePartitioning.field === load_date',
      tp.field === 'load_date',
      `got field '${tp.field}'`);
    check('timePartitioning.type === DAY',
      tp.type === 'DAY',
      `got type '${tp.type}'`);
  } else {
    check('timePartitioning.field === load_date', false, 'timePartitioning missing');
    check('timePartitioning.type === DAY', false, 'timePartitioning missing');
  }

  // load_date is in the schema fields (inlined, not just partition pseudo-column)
  check('load_date is in schema.fields',
    landedMap.has('load_date'),
    'load_date not found in schema fields');

  // Column count (repeat for clarity)
  check('total field count = 11 (10 source + 1 inlined partition)',
    fields.length === 11,
    `got ${fields.length}`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#5 — Legal BigQuery identifiers
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#5: Legal BigQuery identifiers');
  console.log('');

  const allIdentifiers = [BQ_TABLE, ...fields.map(f => f.name)];

  // Check regex
  for (const ident of allIdentifiers) {
    check(`'${ident}' matches BQ identifier regex`,
      IDENT_RE.test(ident),
      `identifier '${ident}' is not a legal BigQuery name`);
  }

  // Check reserved words
  for (const ident of allIdentifiers) {
    check(`'${ident}' is not a BQ reserved word`,
      !BQ_RESERVED_WORDS.has(ident.toUpperCase()),
      `'${ident}' is a BigQuery reserved word`);
  }

  // Check case-fold collisions
  const upperSet = new Map();
  let caseFoldCollision = false;
  for (const ident of fields.map(f => f.name)) {
    const key = ident.toUpperCase();
    if (upperSet.has(key)) {
      check(`no case-fold collision for '${ident}'`, false,
        `collides with '${upperSet.get(key)}'`);
      caseFoldCollision = true;
    } else {
      upperSet.set(key, ident);
    }
  }
  if (!caseFoldCollision) {
    check('no case-fold collisions among column names', true, '');
  }

  // Check length ≤ 1024
  for (const ident of allIdentifiers) {
    check(`'${ident}' length ≤ 1024`,
      ident.length <= 1024,
      `length is ${ident.length}`);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Summary
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  AC#1–AC#5 RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  console.log('═══════════════════════════════════════════════════════════════');

  // ── Teardown: drop the scratch table ──────────────────────────────────
  try {
    await bq.dataset(BQ_DATASET).table(BQ_TABLE).delete();
    console.log(`  Teardown: dropped ${BQ_DATASET}.${BQ_TABLE}`);
  } catch (err) {
    console.log(`  Teardown warning: could not drop ${BQ_DATASET}.${BQ_TABLE}: ${err.message}`);
  }

  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error(`Fatal error: ${err.message}`);
  process.exit(1);
});
