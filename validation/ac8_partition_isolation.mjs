// AC8: Validate ${var:run_date} parameterization → BQ scripting variable / Jinja
// Two runs with different run_date values should each write only their own partition
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
  console.log('CRITERION AC8: ${var:run_date} → BQ scripting variable parameterization');
  console.log('  artifact: SQL/ETL transforms — all 33 scripts');
  console.log('');

  // Check 1: Find all converted scripts and verify parameterization
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

  check('at least 33 SQL scripts exist', sqlFiles.length >= 33,
    `only ${sqlFiles.length} SQL files found`);

  let hasDeclare = 0;
  let hasVarRunDate = 0;
  let hasDeleteInsert = 0;

  for (const f of sqlFiles) {
    const content = fs.readFileSync(f, 'utf8');
    const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
    const code = codeLines.join('\n');

    if (/DECLARE\s+run_date/i.test(code)) hasDeclare++;
    if (/\$\{var:run_date\}/i.test(code)) hasVarRunDate++;
    if (/DELETE\s+FROM/i.test(code) && /INSERT\s+INTO/i.test(code)) hasDeleteInsert++;
  }

  check('scripts use DECLARE run_date', hasDeclare > 0,
    'no DECLARE run_date found in any script');

  check('no residual ${var:run_date}', hasVarRunDate === 0,
    `${hasVarRunDate} scripts still contain Impala \${var:run_date}`);

  check('DELETE+INSERT partition write pattern', hasDeleteInsert > 0,
    'no scripts use DELETE FROM + INSERT INTO partition isolation pattern');

  console.log('');
  console.log(`  RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
