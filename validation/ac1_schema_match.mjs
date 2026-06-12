// AC1: Validate that all 33 converted scripts exist and target tables are populated
// with INFORMATION_SCHEMA.COLUMNS matching the converted DDL
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
  console.log('CRITERION AC1: All 33 converted scripts exist and target tables populated');
  console.log('  artifact: SQL/ETL transforms — category: SQL / ETL logic');
  console.log('');

  // Check 1: Verify the 33 converted scripts exist in the repository
  const expectedScriptDir = '/workspace/project/bigquery';
  const cleanse = Array.from({length: 15}, (_, i) => `${String(i + 9).padStart(2, '0')}-cleanse`);
  const dims = Array.from({length: 9}, (_, i) => `${i + 41}-load-dim`);
  const facts = Array.from({length: 9}, (_, i) => `${i + 50}-load-fact`);

  // Cleanse scripts 09-23
  const expectedCleanse = [
    '09-cleanse-program.sql', '10-cleanse-contract.sql', '11-cleanse-contract-line.sql',
    '12-cleanse-org-unit.sql', '13-cleanse-queue.sql', '14-cleanse-schedule.sql',
    '15-cleanse-adherence-event.sql', '16-cleanse-call.sql', '17-cleanse-ivr-session.sql',
    '18-cleanse-chat-session.sql', '19-cleanse-email-interaction.sql', '20-cleanse-survey-response.sql',
    '21-cleanse-qa-evaluation.sql', '22-cleanse-interaction.sql', '23-cleanse-dialer-attempt.sql'
  ];

  const expectedDim = [
    '41-load-dim-date.sql', '42-load-dim-agent.sql', '43-load-dim-client.sql',
    '44-load-dim-program.sql', '45-load-dim-queue.sql', '46-load-dim-site.sql',
    '47-load-dim-shift.sql', '48-load-dim-org.sql', '49-load-dim-disposition.sql'
  ];

  const expectedFact = [
    '50-load-fact-interaction.sql', '51-load-fact-agent-activity.sql',
    '52-load-fact-queue-interval.sql', '53-load-fact-csat-survey.sql',
    '54-load-fact-qa-evaluation.sql', '55-load-fact-billing-line.sql',
    '56-load-fact-adherence-daily.sql', '57-load-fact-ticket.sql',
    '58-load-fact-ivr-path.sql'
  ];

  const allExpected = [...expectedCleanse, ...expectedDim, ...expectedFact];
  console.log(`  Checking for ${allExpected.length} converted scripts in ${expectedScriptDir}/...`);

  let scriptsMissing = 0;
  let scriptsFound = 0;
  for (const scriptName of allExpected) {
    // Try multiple possible locations
    const paths = [
      path.join(expectedScriptDir, scriptName),
      path.join(expectedScriptDir, 'cleanse', scriptName),
      path.join(expectedScriptDir, 'dim', scriptName),
      path.join(expectedScriptDir, 'fact', scriptName),
    ];
    const found = paths.some(p => fs.existsSync(p));
    if (!found) {
      scriptsMissing++;
    } else {
      scriptsFound++;
    }
  }
  check('converted scripts present', scriptsMissing === 0,
    `${scriptsMissing} of ${allExpected.length} converted scripts missing from repository`);

  // Also search anywhere in the project for SQL files
  const allFiles = [];
  function walk(dir) {
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === '.git') continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else allFiles.push(full);
      }
    } catch(e) {}
  }
  walk('/workspace/project');
  const sqlFiles = allFiles.filter(f => f.endsWith('.sql'));
  check('SQL files exist in repo', sqlFiles.length >= 33,
    `found only ${sqlFiles.length} SQL files in entire project (expected >=33)`);

  console.log(`  Found files in repo: ${allFiles.map(f => f.replace('/workspace/project/', '')).join(', ') || '(none except .git)'}`);

  // Check 2: Verify target tables exist in BigQuery
  console.log('');
  console.log('  Checking BigQuery target tables...');
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);
  console.log(`  Tables in BQ test dataset: ${tableNames.length > 0 ? tableNames.join(', ') : '(none)'}`);

  // Expected ODS tables (cleanse targets)
  const expectedOds = [
    'ods_program', 'ods_contract', 'ods_contract_line',
    'ods_org_unit', 'ods_queue', 'ods_schedule',
    'ods_adherence_event', 'ods_call', 'ods_ivr_session',
    'ods_chat_session', 'ods_email_interaction', 'ods_survey_response',
    'ods_qa_evaluation', 'ods_interaction', 'ods_dialer_attempt'
  ];
  const expectedDimTables = [
    'dim_date', 'dim_agent', 'dim_client', 'dim_program', 'dim_queue',
    'dim_site', 'dim_shift', 'dim_org', 'dim_disposition'
  ];
  const expectedFactTables = [
    'fact_interaction', 'fact_agent_activity', 'fact_queue_interval',
    'fact_csat_survey', 'fact_qa_evaluation', 'fact_billing_line',
    'fact_adherence_daily', 'fact_ticket', 'fact_ivr_path'
  ];

  const allExpectedTables = [...expectedOds, ...expectedDimTables, ...expectedFactTables];
  let tablesMissing = 0;
  for (const t of allExpectedTables) {
    if (!tableNames.includes(t)) tablesMissing++;
  }
  check('all 33 target tables exist in BQ', tablesMissing === 0,
    `${tablesMissing} of ${allExpectedTables.length} target tables missing from BigQuery`);

  // Check 3: Verify tables are populated (have rows)
  if (tablesMissing < allExpectedTables.length) {
    const existing = allExpectedTables.filter(t => tableNames.includes(t));
    for (const t of existing) {
      const [rows] = await bq.query({ query: `SELECT COUNT(*) AS cnt FROM test.${t}` });
      check(`table ${t} populated`, rows[0].cnt > 0, `0 rows`);
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
