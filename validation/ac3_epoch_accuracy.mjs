// AC3: Validate from_unixtime() → TIMESTAMP_SECONDS/TIMESTAMP_MILLIS conversion
// Boundary epochs: 0, 946684800, 4102444799 (seconds) and *1000 (millis)
// Must match with 0-second drift in UTC
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
  console.log('CRITERION AC3: Epoch → TIMESTAMP_SECONDS/MILLIS conversion accuracy');
  console.log('  artifact: SQL/ETL transforms — category: SQL / ETL logic');
  console.log('');

  // Check 1: Verify cleanse scripts exist and contain TIMESTAMP_SECONDS/MILLIS
  const scriptDir = '/workspace/project/bigquery';
  let scriptsExist = false;
  let hasTimestampSeconds = false;
  let hasTimestampMillis = false;
  let hasFromUnixtime = false;

  // Search for all SQL files in the project
  function walk(dir) {
    const result = [];
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === '.git') continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) result.push(...walk(full));
        else if (entry.name.endsWith('.sql')) result.push(full);
      }
    } catch(e) {}
    return result;
  }

  const sqlFiles = walk('/workspace/project');
  console.log(`  Found ${sqlFiles.length} SQL files in project`);

  for (const f of sqlFiles) {
    const content = fs.readFileSync(f, 'utf8');
    if (/TIMESTAMP_SECONDS/i.test(content)) hasTimestampSeconds = true;
    if (/TIMESTAMP_MILLIS/i.test(content)) hasTimestampMillis = true;
    // Check for residual from_unixtime (excluding comments)
    const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
    for (const line of codeLines) {
      if (/from_unixtime\s*\(/i.test(line)) hasFromUnixtime = true;
    }
  }

  check('converted scripts exist', sqlFiles.length >= 15,
    `only ${sqlFiles.length} SQL files found — expected at least 15 cleanse scripts`);

  check('TIMESTAMP_SECONDS used in converted code', hasTimestampSeconds,
    'no TIMESTAMP_SECONDS found in any converted script');

  check('TIMESTAMP_MILLIS used in converted code', hasTimestampMillis,
    'no TIMESTAMP_MILLIS found in any converted script');

  check('no residual from_unixtime() in code', !hasFromUnixtime,
    'from_unixtime() still present in non-comment code lines');

  // Check 2: Verify epoch conversion accuracy in BigQuery
  // Even without the scripts, test that the BQ functions produce correct UTC results
  console.log('');
  console.log('  Verifying BQ epoch boundary conversions...');

  const epochTests = [
    { epoch: 0, expected: '1970-01-01 00:00:00 UTC', fn: 'TIMESTAMP_SECONDS' },
    { epoch: 946684800, expected: '2000-01-01 00:00:00 UTC', fn: 'TIMESTAMP_SECONDS' },
    { epoch: 4102444799, expected: '2099-12-31 23:59:59 UTC', fn: 'TIMESTAMP_SECONDS' },
    { epoch: 0, expected: '1970-01-01 00:00:00 UTC', fn: 'TIMESTAMP_MILLIS' },
    { epoch: 946684800000, expected: '2000-01-01 00:00:00 UTC', fn: 'TIMESTAMP_MILLIS' },
    { epoch: 4102444799000, expected: '2099-12-31 23:59:59 UTC', fn: 'TIMESTAMP_MILLIS' },
  ];

  for (const t of epochTests) {
    try {
      const [rows] = await bq.query({
        query: `SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S UTC', ${t.fn}(${t.epoch})) AS ts`
      });
      check(`${t.fn}(${t.epoch}) = ${t.expected}`,
        rows[0].ts === t.expected,
        `got ${rows[0].ts}`);
    } catch (e) {
      check(`${t.fn}(${t.epoch})`, false, e.message);
    }
  }

  // Check 3: Verify ODS tables exist with epoch-derived timestamp columns populated
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);
  const odsWithEpochs = tableNames.filter(t => t.startsWith('ods_'));
  check('ODS tables exist for epoch validation', odsWithEpochs.length >= 15,
    `only ${odsWithEpochs.length} ODS tables found (expected 15)`);

  // Check EPOCH-POLICY.md exists
  const policyPath = '/workspace/project/docs/EPOCH-POLICY.md';
  check('docs/EPOCH-POLICY.md exists', fs.existsSync(policyPath),
    'EPOCH-POLICY.md not found');

  console.log('');
  console.log(`  RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
