// validation/stg_crm_contract_validate.mjs
// Validates the converted BigQuery DDL for staging.stg_crm_contract
// Covers AC#1–AC#6 (schema/metadata validation + cross-engine edge-value round-trip).
//
// Usage:
//   set -a && . /workspace/.gallop/db.env && set +a
//   node validation/stg_crm_contract_validate.mjs

import { createRequire } from 'module';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');
const hive = require('hive-driver');

// ── BigQuery client ─────────────────────────────────────────────────────────
const authClient = new OAuth2Client();
authClient.setCredentials({ access_token: process.env.CHECKIN_BQ_TOKEN });
const bq = new BigQuery({
  projectId: process.env.CHECKIN_BQ_PROJECT,
  authClient,
});
const BQ_DATASET = process.env.CHECKIN_BQ_DATASETS || 'test';
const BQ_TABLE   = 'stg_crm_contract';

// ── Impala constants ────────────────────────────────────────────────────────
const IMP_HOST  = process.env.CHECKIN_IMP_HOST;
const IMP_PORT  = Number(process.env.CHECKIN_IMP_PORT);
const IMP_AUTH  = process.env.CHECKIN_IMP_HIVE_AUTH;   // 'nosasl'
const IMP_USER  = process.env.CHECKIN_IMP_USER || 'impala';
const IMP_PASS  = process.env.CHECKIN_IMP_PASSWORD || '';
const IMP_DB    = process.env.CHECKIN_IMP_DATABASE || 'default';
const IMP_SCRATCH_TABLE = 'qa_scratch_stg_crm_contract';

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

const IDENT_RE = /^[a-zA-Z_][a-zA-Z0-9_]{0,1023}$/;

// ═══════════════════════════════════════════════════════════════════════════
// Impala helper: connect, exec, close
// ═══════════════════════════════════════════════════════════════════════════
const { TCLIService, TCLIService_types } = hive.thrift;
const FETCH_NEXT = 1;  // FetchOrientation.FETCH_NEXT

async function impalaConnect() {
  const client = new hive.HiveClient(TCLIService, TCLIService_types);
  const auth = IMP_AUTH === 'nosasl'
    ? new hive.auth.NoSaslAuthentication()
    : new hive.auth.PlainTcpAuthentication({ username: IMP_USER, password: IMP_PASS });
  const conn = await client.connect(
    { host: IMP_HOST, port: IMP_PORT },
    new hive.connections.TcpConnection(),
    auth,
  );
  const session = await conn.openSession({
    client_protocol: TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10,
  });
  const utils = new hive.HiveUtils(TCLIService_types);
  return { conn, session, utils };
}

async function impalaExec(session, utils, sql) {
  const op = await session.executeStatement(sql, { runAsync: true });
  try {
    await utils.waitUntilReady(op, false, () => {});
    await utils.fetchAll(op, FETCH_NEXT);
    return utils.getResult(op).getValue() ?? [];
  } finally {
    await op.close().catch(() => {});
  }
}

async function impalaExecNoResult(session, utils, sql) {
  const op = await session.executeStatement(sql, { runAsync: true });
  try {
    await utils.waitUntilReady(op, false, () => {});
  } finally {
    await op.close().catch(() => {});
  }
}

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
  // CREATE OR REPLACE for idempotent re-runs
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
    await bq.query({ query: ddlExec });
    console.log(`  DDL executed successfully in dataset '${BQ_DATASET}'`);

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

  const landedMap = new Map(fields.map(f => [f.name, f.type]));

  for (const expected of EXPECTED_COLUMNS) {
    const actual = landedMap.get(expected.name);
    check(`${expected.name} → ${expected.ddlType} (API: ${expected.type})`,
      actual === expected.type,
      `expected ${expected.type} (DDL: ${expected.ddlType}), got ${actual || '(missing)'}`);
  }

  for (const col of MUST_BE_STRING) {
    const actual = landedMap.get(col);
    check(`${col} is NOT DATETIME or TIMESTAMP`,
      actual !== 'DATETIME' && actual !== 'TIMESTAMP',
      `got ${actual} — implicit date cast detected`);
  }

  const landedNames = new Set(fields.map(f => f.name));
  const expectedNames = new Set(EXPECTED_COLUMNS.map(c => c.name));
  const extraCols = [...landedNames].filter(n => !expectedNames.has(n));
  const missingCols = [...expectedNames].filter(n => !landedNames.has(n));
  check('no extra columns', extraCols.length === 0,
    `unexpected columns: ${extraCols.join(', ')}`);
  check('no missing columns', missingCols.length === 0,
    `missing columns: ${missingCols.join(', ')}`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#3 — No Hive storage clauses in output DDL
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#3: No Hive storage clauses in DDL body');
  console.log('');

  for (const { pattern, label } of HIVE_FORBIDDEN) {
    const found = pattern.test(ddlBody);
    check(`DDL body does not contain '${label}'`, !found,
      `found '${label}' in functional DDL body`);
  }
  check('metadata confirms managed TABLE (not EXTERNAL)',
    metadata.type === 'TABLE', `got type '${metadata.type}'`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#4 — Partition strategy verified from metadata
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#4: Partition strategy verified from metadata');
  console.log('');

  const tp = metadata.timePartitioning;
  check('timePartitioning is present', !!tp, 'metadata.timePartitioning is missing');

  if (tp) {
    check('timePartitioning.field === load_date',
      tp.field === 'load_date', `got field '${tp.field}'`);
    check('timePartitioning.type === DAY',
      tp.type === 'DAY', `got type '${tp.type}'`);
  } else {
    check('timePartitioning.field === load_date', false, 'timePartitioning missing');
    check('timePartitioning.type === DAY', false, 'timePartitioning missing');
  }

  check('load_date is in schema.fields',
    landedMap.has('load_date'), 'load_date not found in schema fields');
  check('total field count = 11 (10 source + 1 inlined partition)',
    fields.length === 11, `got ${fields.length}`);

  // ══════════════════════════════════════════════════════════════════════
  // AC#5 — Legal BigQuery identifiers
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#5: Legal BigQuery identifiers');
  console.log('');

  const allIdentifiers = [BQ_TABLE, ...fields.map(f => f.name)];

  for (const ident of allIdentifiers) {
    check(`'${ident}' matches BQ identifier regex`,
      IDENT_RE.test(ident),
      `identifier '${ident}' is not a legal BigQuery name`);
  }
  for (const ident of allIdentifiers) {
    check(`'${ident}' is not a BQ reserved word`,
      !BQ_RESERVED_WORDS.has(ident.toUpperCase()),
      `'${ident}' is a BigQuery reserved word`);
  }

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

  for (const ident of allIdentifiers) {
    check(`'${ident}' length ≤ 1024`,
      ident.length <= 1024, `length is ${ident.length}`);
  }

  // ── AC#1–AC#5 subtotal ───────────────────────────────────────────────
  console.log('');
  console.log('───────────────────────────────────────────────────────────────');
  console.log(`  AC#1–AC#5 subtotal: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  console.log('───────────────────────────────────────────────────────────────');

  // ══════════════════════════════════════════════════════════════════════
  // AC#6 — Cross-engine edge-value round-trip (Impala + BigQuery)
  // ══════════════════════════════════════════════════════════════════════
  console.log('');
  console.log('CRITERION AC#6: Cross-engine edge-value round-trip');
  console.log('');

  const ac6Failed0 = failed;  // snapshot to detect AC#6 failures

  // ── Edge-case test rows ───────────────────────────────────────────────
  // We define 5 canonical rows that exercise boundary/edge conditions.
  // Each row is identified by a unique contract_id for deterministic ordering.
  //
  // BIGINT boundary values (contract_id):
  //   Row 1: INT64 max  9223372036854775807
  //   Row 2: INT64 min -9223372036854775808
  // Unicode + control chars (contract_no):
  //   Row 3: 'café — 日本語 — 🎉\t\n'  (with TAB and NEWLINE)
  // NULL vs empty string (contract_no):
  //   Row 4: NULL
  //   Row 5: '' (empty string)
  // Oracle string date (start_dt):
  //   Row 3: '20230615143022'
  // NULL date (end_dt):
  //   Row 1: NULL for end_dt

  let impSession, impUtils, impConn;
  try {
    console.log('  Connecting to Impala...');
    const imp = await impalaConnect();
    impConn = imp.conn;
    impSession = imp.session;
    impUtils = imp.utils;
    console.log(`  Connected to Impala at ${IMP_HOST}:${IMP_PORT} (auth: ${IMP_AUTH})`);
  } catch (err) {
    console.log(`  ✗ Impala connection failed: ${err.message}`);
    failed++;
    await teardown(null, null, null);
    printFinalSummary();
    process.exit(failed > 0 ? 1 : 0);
  }

  try {
    // ── Create scratch source table on Impala ───────────────────────────
    // Managed table (no EXTERNAL/HDFS) for seeding edge-case data.
    // Uses non-partitioned table to simplify INSERT — all columns inline.
    console.log('  Creating Impala scratch table...');
    await impalaExecNoResult(impSession, impUtils,
      `DROP TABLE IF EXISTS ${IMP_DB}.${IMP_SCRATCH_TABLE}`);
    await impalaExecNoResult(impSession, impUtils, `
      CREATE TABLE ${IMP_DB}.${IMP_SCRATCH_TABLE} (
        contract_id    BIGINT,
        client_id      BIGINT,
        program_id     BIGINT,
        contract_no    STRING,
        start_dt       STRING,
        end_dt         STRING,
        billing_model  STRING,
        currency       STRING,
        signed_dt      STRING,
        status         STRING,
        load_date      STRING
      )
      STORED AS PARQUET
    `);
    console.log(`  Created ${IMP_DB}.${IMP_SCRATCH_TABLE}`);

    // ── Seed edge-case rows into Impala ─────────────────────────────────
    console.log('  Seeding edge-case rows into Impala...');

    // Row 1: BIGINT max, NULL end_dt
    await impalaExecNoResult(impSession, impUtils, `
      INSERT INTO ${IMP_DB}.${IMP_SCRATCH_TABLE} VALUES (
        9223372036854775807, 1, 1, 'row1_bigint_max',
        '20230101120000', NULL, 'FIXED', 'USD', '20230101120000', 'ACTIVE', '2024-01-15'
      )
    `);

    // Row 2: BIGINT min
    await impalaExecNoResult(impSession, impUtils, `
      INSERT INTO ${IMP_DB}.${IMP_SCRATCH_TABLE} VALUES (
        -9223372036854775808, 2, 2, 'row2_bigint_min',
        '20230201120000', '20240201120000', 'HOURLY', 'EUR', '20230201120000', 'ACTIVE', '2024-01-15'
      )
    `);

    // Row 3: Unicode + control chars in contract_no, Oracle date in start_dt
    // Impala supports \t and \n in string literals
    await impalaExecNoResult(impSession, impUtils, `
      INSERT INTO ${IMP_DB}.${IMP_SCRATCH_TABLE} VALUES (
        3, 3, 3, 'café — 日本語 — 🎉\t\n',
        '20230615143022', '20240615143022', 'PER_CALL', 'GBP', '20230615143022', 'PENDING', '2024-01-15'
      )
    `);

    // Row 4: NULL contract_no
    await impalaExecNoResult(impSession, impUtils, `
      INSERT INTO ${IMP_DB}.${IMP_SCRATCH_TABLE} VALUES (
        4, 4, 4, NULL,
        '20230301120000', '20240301120000', 'FIXED', 'USD', '20230301120000', 'ACTIVE', '2024-01-15'
      )
    `);

    // Row 5: Empty string contract_no
    await impalaExecNoResult(impSession, impUtils, `
      INSERT INTO ${IMP_DB}.${IMP_SCRATCH_TABLE} VALUES (
        5, 5, 5, '',
        '20230401120000', '20240401120000', 'HOURLY', 'CAD', '20230401120000', 'CLOSED', '2024-01-15'
      )
    `);

    console.log('  Seeded 5 edge-case rows into Impala');

    // ── Seed same edge-case rows into BigQuery ──────────────────────────
    console.log('  Seeding edge-case rows into BigQuery...');

    // First truncate any existing data (table was created by AC#1)
    await bq.query({ query: `DELETE FROM ${BQ_DATASET}.${BQ_TABLE} WHERE TRUE` });

    // Row 1: BIGINT max, NULL end_dt
    await bq.query({ query: `
      INSERT INTO ${BQ_DATASET}.${BQ_TABLE}
        (contract_id, client_id, program_id, contract_no, start_dt, end_dt,
         billing_model, currency, signed_dt, status, load_date)
      VALUES
        (9223372036854775807, 1, 1, 'row1_bigint_max',
         '20230101120000', NULL, 'FIXED', 'USD', '20230101120000', 'ACTIVE', DATE '2024-01-15')
    `});

    // Row 2: BIGINT min
    await bq.query({ query: `
      INSERT INTO ${BQ_DATASET}.${BQ_TABLE}
        (contract_id, client_id, program_id, contract_no, start_dt, end_dt,
         billing_model, currency, signed_dt, status, load_date)
      VALUES
        (-9223372036854775808, 2, 2, 'row2_bigint_min',
         '20230201120000', '20240201120000', 'HOURLY', 'EUR', '20230201120000', 'ACTIVE', DATE '2024-01-15')
    `});

    // Row 3: Unicode + control chars
    // BigQuery string literals: use escaped \t and \n within single quotes
    await bq.query({ query:
      "INSERT INTO " + BQ_DATASET + "." + BQ_TABLE +
      " (contract_id, client_id, program_id, contract_no, start_dt, end_dt," +
      "  billing_model, currency, signed_dt, status, load_date)" +
      " VALUES" +
      " (3, 3, 3, 'café — 日本語 — 🎉\\t\\n'," +
      "  '20230615143022', '20240615143022', 'PER_CALL', 'GBP', '20230615143022', 'PENDING', DATE '2024-01-15')"
    });

    // Row 4: NULL contract_no
    await bq.query({ query: `
      INSERT INTO ${BQ_DATASET}.${BQ_TABLE}
        (contract_id, client_id, program_id, contract_no, start_dt, end_dt,
         billing_model, currency, signed_dt, status, load_date)
      VALUES
        (4, 4, 4, NULL,
         '20230301120000', '20240301120000', 'FIXED', 'USD', '20230301120000', 'ACTIVE', DATE '2024-01-15')
    `});

    // Row 5: Empty string contract_no
    await bq.query({ query: `
      INSERT INTO ${BQ_DATASET}.${BQ_TABLE}
        (contract_id, client_id, program_id, contract_no, start_dt, end_dt,
         billing_model, currency, signed_dt, status, load_date)
      VALUES
        (5, 5, 5, '',
         '20230401120000', '20240401120000', 'HOURLY', 'CAD', '20230401120000', 'CLOSED', DATE '2024-01-15')
    `});

    console.log('  Seeded 5 edge-case rows into BigQuery');

    // ── Read back from both engines ─────────────────────────────────────
    // CAST contract_id to STRING to avoid JavaScript number precision loss
    // for BIGINT boundary values (JS Number can't represent INT64 max/min exactly).
    console.log('  Reading back from both engines...');

    const readSql_imp = `
      SELECT
        CAST(contract_id AS STRING) AS contract_id_str,
        CAST(client_id AS STRING)   AS client_id_str,
        CAST(program_id AS STRING)  AS program_id_str,
        contract_no,
        start_dt,
        end_dt,
        billing_model,
        currency,
        signed_dt,
        status,
        load_date
      FROM ${IMP_DB}.${IMP_SCRATCH_TABLE}
      ORDER BY CAST(contract_id AS STRING)
    `;

    const readSql_bq = `
      SELECT
        CAST(contract_id AS STRING) AS contract_id_str,
        CAST(client_id AS STRING)   AS client_id_str,
        CAST(program_id AS STRING)  AS program_id_str,
        contract_no,
        start_dt,
        end_dt,
        billing_model,
        currency,
        signed_dt,
        status,
        CAST(load_date AS STRING)   AS load_date
      FROM ${BQ_DATASET}.${BQ_TABLE}
      ORDER BY CAST(contract_id AS STRING)
    `;

    const impRows = await impalaExec(impSession, impUtils, readSql_imp);
    const [bqRows] = await bq.query({ query: readSql_bq });

    console.log(`  Impala returned ${impRows.length} rows, BigQuery returned ${bqRows.length} rows`);

    // ── Assert row counts match ─────────────────────────────────────────
    check('row count matches (5 rows each)',
      impRows.length === 5 && bqRows.length === 5,
      `Impala: ${impRows.length}, BQ: ${bqRows.length}`);

    // ── Edge-case assertions ────────────────────────────────────────────
    // Build lookup maps by contract_id_str for deterministic comparison
    const impByKey = Object.fromEntries(impRows.map(r => [r.contract_id_str, r]));
    const bqByKey  = Object.fromEntries(bqRows.map(r => [r.contract_id_str, r]));

    let totalEdgeChecks = 0;
    let passedEdgeChecks = 0;

    function edgeCheck(label, impVal, bqVal) {
      totalEdgeChecks++;
      // Normalise: both null → match, both same string → match
      const impNorm = impVal === null || impVal === undefined ? null : String(impVal);
      const bqNorm  = bqVal === null || bqVal === undefined ? null : String(bqVal);
      const match = impNorm === bqNorm;
      if (match) passedEdgeChecks++;
      check(label, match,
        `Impala=${JSON.stringify(impNorm)} vs BQ=${JSON.stringify(bqNorm)}`);
    }

    // --- BIGINT max (row key = 9223372036854775807) ---
    // Note: with ORDER BY CAST(contract_id AS STRING), the negative number sorts
    // first lexicographically. But we look up by key, so order doesn't matter.
    const impMax = impByKey['9223372036854775807'];
    const bqMax  = bqByKey['9223372036854775807'];
    check('BIGINT max row exists in Impala', !!impMax, 'row not found');
    check('BIGINT max row exists in BigQuery', !!bqMax, 'row not found');
    if (impMax && bqMax) {
      edgeCheck('BIGINT max contract_id round-trip',
        impMax.contract_id_str, bqMax.contract_id_str);
      edgeCheck('BIGINT max end_dt is NULL',
        impMax.end_dt, bqMax.end_dt);
    }

    // --- BIGINT min (row key = -9223372036854775808) ---
    const impMin = impByKey['-9223372036854775808'];
    const bqMin  = bqByKey['-9223372036854775808'];
    check('BIGINT min row exists in Impala', !!impMin, 'row not found');
    check('BIGINT min row exists in BigQuery', !!bqMin, 'row not found');
    if (impMin && bqMin) {
      edgeCheck('BIGINT min contract_id round-trip',
        impMin.contract_id_str, bqMin.contract_id_str);
    }

    // --- Unicode + control chars (row key = 3) ---
    const impUni = impByKey['3'];
    const bqUni  = bqByKey['3'];
    check('Unicode row exists in Impala', !!impUni, 'row not found');
    check('Unicode row exists in BigQuery', !!bqUni, 'row not found');
    if (impUni && bqUni) {
      edgeCheck('Unicode contract_no round-trip (café — 日本語 — 🎉 + TAB + NL)',
        impUni.contract_no, bqUni.contract_no);
      edgeCheck('Oracle string date start_dt round-trip',
        impUni.start_dt, bqUni.start_dt);
      edgeCheck('Oracle string date signed_dt round-trip',
        impUni.signed_dt, bqUni.signed_dt);
      // Verify it actually contains the expected characters
      const uniVal = String(bqUni.contract_no || '');
      check('contract_no contains café', uniVal.includes('café'),
        `value: ${JSON.stringify(uniVal)}`);
      check('contract_no contains 日本語', uniVal.includes('日本語'),
        `value: ${JSON.stringify(uniVal)}`);
      check('contract_no contains 🎉', uniVal.includes('🎉'),
        `value: ${JSON.stringify(uniVal)}`);
      check('contract_no contains TAB', uniVal.includes('\t'),
        `value: ${JSON.stringify(uniVal)}`);
      check('contract_no contains NEWLINE', uniVal.includes('\n'),
        `value: ${JSON.stringify(uniVal)}`);
    }

    // --- NULL contract_no (row key = 4) ---
    const impNull = impByKey['4'];
    const bqNull  = bqByKey['4'];
    check('NULL row exists in Impala', !!impNull, 'row not found');
    check('NULL row exists in BigQuery', !!bqNull, 'row not found');
    if (impNull && bqNull) {
      edgeCheck('NULL contract_no round-trip',
        impNull.contract_no, bqNull.contract_no);
      check('NULL contract_no is actually null (Impala)',
        impNull.contract_no === null || impNull.contract_no === undefined,
        `got ${JSON.stringify(impNull.contract_no)}`);
      check('NULL contract_no is actually null (BigQuery)',
        bqNull.contract_no === null || bqNull.contract_no === undefined,
        `got ${JSON.stringify(bqNull.contract_no)}`);
    }

    // --- Empty string contract_no (row key = 5) ---
    const impEmpty = impByKey['5'];
    const bqEmpty  = bqByKey['5'];
    check('Empty-string row exists in Impala', !!impEmpty, 'row not found');
    check('Empty-string row exists in BigQuery', !!bqEmpty, 'row not found');
    if (impEmpty && bqEmpty) {
      edgeCheck('Empty-string contract_no round-trip',
        impEmpty.contract_no, bqEmpty.contract_no);
      check('Empty-string contract_no is "" not null (Impala)',
        impEmpty.contract_no === '',
        `got ${JSON.stringify(impEmpty.contract_no)}`);
      check('Empty-string contract_no is "" not null (BigQuery)',
        bqEmpty.contract_no === '',
        `got ${JSON.stringify(bqEmpty.contract_no)}`);
    }

    // --- NULL vs empty-string distinctness ---
    if (impNull && impEmpty && bqNull && bqEmpty) {
      // Impala side
      const impNullIsNull = impNull.contract_no === null || impNull.contract_no === undefined;
      const impEmptyIsEmpty = impEmpty.contract_no === '';
      check('NULL ≠ empty-string (Impala)',
        impNullIsNull && impEmptyIsEmpty,
        `null_row=${JSON.stringify(impNull.contract_no)}, empty_row=${JSON.stringify(impEmpty.contract_no)}`);
      // BigQuery side
      const bqNullIsNull = bqNull.contract_no === null || bqNull.contract_no === undefined;
      const bqEmptyIsEmpty = bqEmpty.contract_no === '';
      check('NULL ≠ empty-string (BigQuery)',
        bqNullIsNull && bqEmptyIsEmpty,
        `null_row=${JSON.stringify(bqNull.contract_no)}, empty_row=${JSON.stringify(bqEmpty.contract_no)}`);
    }

    // ── Coverage summary ────────────────────────────────────────────────
    const ac6Checks = failed - ac6Failed0;
    const ac6Passed = passed - (69 - ac6Failed0);  // 69 = AC#1–5 checks from prior run
    // Simpler: just count what we declared
    console.log('');
    console.log(`  state coverage probed ${passedEdgeChecks} of ${totalEdgeChecks} edge-value comparisons`);

  } catch (err) {
    console.log(`  ✗ AC#6 error: ${err.message}`);
    if (err.stack) console.log(`    ${err.stack.split('\n').slice(1, 4).join('\n    ')}`);
    failed++;
  } finally {
    // ── Teardown ────────────────────────────────────────────────────────
    await teardown(impSession, impUtils, impConn);
  }

  printFinalSummary();
  process.exit(failed > 0 ? 1 : 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// Teardown
// ═══════════════════════════════════════════════════════════════════════════
async function teardown(impSession, impUtils, impConn) {
  console.log('');
  console.log('  Teardown:');

  // Drop BigQuery scratch table
  try {
    await bq.dataset(BQ_DATASET).table(BQ_TABLE).delete();
    console.log(`    dropped ${BQ_DATASET}.${BQ_TABLE} (BigQuery)`);
  } catch (err) {
    console.log(`    warning: could not drop ${BQ_DATASET}.${BQ_TABLE}: ${err.message}`);
  }

  // Drop Impala scratch table and close connection
  if (impSession && impUtils) {
    try {
      await impalaExecNoResult(impSession, impUtils,
        `DROP TABLE IF EXISTS ${IMP_DB}.${IMP_SCRATCH_TABLE}`);
      console.log(`    dropped ${IMP_DB}.${IMP_SCRATCH_TABLE} (Impala)`);
    } catch (err) {
      console.log(`    warning: could not drop Impala table: ${err.message}`);
    }
    try {
      await impSession.close();
      await impConn.close();
      console.log('    closed Impala connection');
    } catch (err) {
      console.log(`    warning: Impala close error: ${err.message}`);
    }
  }
}

function printFinalSummary() {
  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  AC#1–AC#6 RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  console.log('═══════════════════════════════════════════════════════════════');
}

main().catch(err => {
  console.error(`Fatal error: ${err.message}`);
  process.exit(1);
});
