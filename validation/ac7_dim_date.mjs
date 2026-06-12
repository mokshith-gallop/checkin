// AC7: Validate dim_date (script 41) — LOAD DATA INPATH replacement
// The replacement load (bq load / external table / INSERT) must match source parquet
import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');
const fs = require('fs');
const path = require('path');

const authClient = new OAuth2Client();
authClient.setCredentials({ access_token: process.env.BQ_BQ_TOKEN });
const bq = new BigQuery({ projectId: process.env.BQ_BQ_PROJECT, authClient });

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

async function main() {
  console.log('CRITERION AC7: dim_date LOAD DATA INPATH replacement');
  console.log('  artifact: SQL/ETL transform + data load — 41-load-dim-date.sql');
  console.log('');

  // Check 1: Script exists
  const candidates = [
    '/workspace/project/bigquery/41-load-dim-date.sql',
    '/workspace/project/bigquery/dim/41-load-dim-date.sql',
  ];
  let scriptPath = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) { scriptPath = c; break; }
  }

  check('41-load-dim-date.sql exists', scriptPath !== null,
    'converted script not found in repository');

  if (scriptPath) {
    const content = fs.readFileSync(scriptPath, 'utf8');
    const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
    const code = codeLines.join('\n');

    // Should NOT have LOAD DATA INPATH (Impala-ism)
    check('no LOAD DATA INPATH', !/LOAD\s+DATA\s+INPATH/i.test(code),
      'LOAD DATA INPATH still present');

    // Should have a BQ-compatible load mechanism
    const hasBqLoad = /INSERT\s+INTO/i.test(code) ||
                      /CREATE\s+OR\s+REPLACE/i.test(code) ||
                      /EXTERNAL\s+TABLE/i.test(code) ||
                      /bq\s+load/i.test(code);
    check('BQ-compatible load mechanism present', hasBqLoad,
      'no INSERT INTO / CREATE OR REPLACE / EXTERNAL TABLE / bq load found');
  }

  // Check 2: dim_date table exists in BQ
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);
  check('dim_date table exists in BQ', tableNames.includes('dim_date'),
    'target table not found');

  if (tableNames.includes('dim_date')) {
    // Check it has rows
    try {
      const [rows] = await bq.query({ query: `SELECT COUNT(*) AS cnt FROM test.dim_date` });
      check('dim_date is populated', rows[0].cnt > 0,
        `table is empty (0 rows)`);
    } catch (e) {
      check('dim_date queryable', false, e.message);
    }
  }

  console.log('');
  console.log(`  RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
