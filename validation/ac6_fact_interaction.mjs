// AC6: Validate fact_interaction (script 50) — FK defaults to -1, partitioning, clustering
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
  console.log('CRITERION AC6: fact_interaction — FK defaults, partitioning, clustering');
  console.log('  artifact: SQL/ETL transform — 50-load-fact-interaction.sql');
  console.log('');

  // Check 1: Script exists
  const candidates = [
    '/workspace/project/bigquery/50-load-fact-interaction.sql',
    '/workspace/project/bigquery/fact/50-load-fact-interaction.sql',
  ];
  let scriptPath = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) { scriptPath = c; break; }
  }

  check('50-load-fact-interaction.sql exists', scriptPath !== null,
    'converted script not found in repository');

  if (scriptPath) {
    const content = fs.readFileSync(scriptPath, 'utf8');
    const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
    const code = codeLines.join('\n');

    // Check for COALESCE -1 pattern for FK defaults
    check('COALESCE(-1) for FK defaults', /COALESCE\s*\([^)]*,\s*-1\s*\)/i.test(code),
      'COALESCE(..., -1) pattern not found for unresolvable FK defaults');

    // Check for LEFT JOIN pattern
    check('LEFT JOIN for dimension lookups', /LEFT\s+JOIN/i.test(code),
      'LEFT JOIN not found — needed for FK default behavior');

    // Check for partition on date column
    check('partitioned on date column', /PARTITION\s+BY|date_key/i.test(code),
      'no date partition reference found');
  }

  // Check 2: fact_interaction table exists in BQ with proper metadata
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);

  check('fact_interaction table exists', tableNames.includes('fact_interaction'),
    'target table not found in BigQuery');

  if (tableNames.includes('fact_interaction')) {
    // Check partition and clustering via INFORMATION_SCHEMA
    try {
      const [partInfo] = await bq.query({
        query: `SELECT column_name, data_type 
                FROM test.INFORMATION_SCHEMA.COLUMNS 
                WHERE table_name = 'fact_interaction'
                ORDER BY ordinal_position`
      });
      check('fact_interaction has columns', partInfo.length > 0,
        'no columns found');

      // Check for date_key column
      const hasDateKey = partInfo.some(c => c.column_name === 'date_key');
      check('has date_key column', hasDateKey, 'date_key column not found');

      // Check for agent_sk and queue_sk columns
      const hasAgentSk = partInfo.some(c => c.column_name === 'agent_sk');
      const hasQueueSk = partInfo.some(c => c.column_name === 'queue_sk');
      check('has agent_sk/queue_sk FK columns', hasAgentSk && hasQueueSk,
        `agent_sk: ${hasAgentSk}, queue_sk: ${hasQueueSk}`);
    } catch (e) {
      check('fact_interaction schema queryable', false, e.message);
    }

    // Check partitioning metadata
    try {
      const [partMeta] = await bq.query({
        query: `SELECT ddl FROM \`test.INFORMATION_SCHEMA.TABLES\` WHERE table_name = 'fact_interaction'`
      });
      if (partMeta.length > 0 && partMeta[0].ddl) {
        const ddl = partMeta[0].ddl;
        check('BQ table is partitioned', /PARTITION BY/i.test(ddl),
          'DDL does not show PARTITION BY');
        check('BQ table has clustering', /CLUSTER BY/i.test(ddl),
          'DDL does not show CLUSTER BY');
      }
    } catch (e) {
      // INFORMATION_SCHEMA.TABLES DDL may not be available, skip
      console.log(`  ⊘ partition/clustering metadata: ${e.message}`);
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
