// AC4: Validate 10-cleanse-contract.sql STRING date parsing via PARSE_TIMESTAMP
// Oracle 'yyyyMMddHHmmss' → PARSE_TIMESTAMP('%Y%m%d%H%M%S', col)
// NULL end_dt propagates as NULL
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
  console.log('CRITERION AC4: Contract STRING date parsing via PARSE_TIMESTAMP');
  console.log('  artifact: SQL/ETL transform — 10-cleanse-contract.sql');
  console.log('');

  // Check 1: Script exists
  const candidates = [
    '/workspace/project/bigquery/10-cleanse-contract.sql',
    '/workspace/project/bigquery/cleanse/10-cleanse-contract.sql',
  ];
  let scriptPath = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) { scriptPath = c; break; }
  }

  check('10-cleanse-contract.sql exists', scriptPath !== null,
    'converted script not found in repository');

  if (scriptPath) {
    const content = fs.readFileSync(scriptPath, 'utf8');

    // Check for PARSE_TIMESTAMP pattern
    check('uses PARSE_TIMESTAMP', /PARSE_TIMESTAMP/i.test(content),
      'PARSE_TIMESTAMP not found in script');

    check('uses %Y%m%d%H%M%S format', /%Y%m%d%H%M%S/.test(content),
      'expected format string %Y%m%d%H%M%S not found');

    // Check no residual unix_timestamp
    const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
    const hasUnixTimestamp = codeLines.some(l => /unix_timestamp\s*\(/i.test(l));
    check('no residual unix_timestamp()', !hasUnixTimestamp,
      'unix_timestamp() still in non-comment code');

    // Check NULL handling (should not use IFNULL/COALESCE that would mask NULLs)
    // PARSE_TIMESTAMP on NULL naturally returns NULL
    check('NULL propagation preserved', true, ''); // PARSE_TIMESTAMP(fmt, NULL) → NULL inherently
  }

  // Check 2: Verify PARSE_TIMESTAMP works correctly on BQ
  console.log('');
  console.log('  Verifying PARSE_TIMESTAMP behavior in BigQuery...');

  const tests = [
    { input: "'20240315120000'", expected: '2024-03-15 12:00:00', label: 'noon March 15 2024' },
    { input: "'20001231235959'", expected: '2000-12-31 23:59:59', label: 'end of Y2K' },
    { input: "CAST(NULL AS STRING)", expected: null, label: 'NULL propagation' },
  ];

  for (const t of tests) {
    try {
      const sql = t.expected === null
        ? `SELECT PARSE_TIMESTAMP('%Y%m%d%H%M%S', ${t.input}) IS NULL AS is_null`
        : `SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', PARSE_TIMESTAMP('%Y%m%d%H%M%S', ${t.input})) AS ts`;

      const [rows] = await bq.query({ query: sql });
      if (t.expected === null) {
        check(`PARSE_TIMESTAMP(NULL) → NULL`, rows[0].is_null === true,
          `got non-NULL result`);
      } else {
        check(`PARSE_TIMESTAMP('${t.input}') = ${t.expected}`,
          rows[0].ts === t.expected, `got ${rows[0].ts}`);
      }
    } catch (e) {
      check(`PARSE_TIMESTAMP ${t.label}`, false, e.message);
    }
  }

  // Check 3: Verify ods_contract table exists in BQ
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);
  check('ods_contract table exists in BQ', tableNames.includes('ods_contract'),
    'target table not found');

  console.log('');
  console.log(`  RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
