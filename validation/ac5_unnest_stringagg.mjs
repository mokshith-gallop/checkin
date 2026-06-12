// AC5: Validate nested-collection FROM syntax → UNNEST and group_concat → STRING_AGG
// Scripts: 18-cleanse-chat-session.sql, 21-cleanse-qa-evaluation.sql, 17-cleanse-ivr-session.sql
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
  console.log('CRITERION AC5: Nested collection → UNNEST and group_concat → STRING_AGG');
  console.log('  artifact: SQL/ETL transforms — 17, 18, 21-cleanse scripts');
  console.log('');

  const scripts = {
    '18-cleanse-chat-session.sql': {
      patterns: ['UNNEST', 'messages'],
      antiPatterns: [/(?<!--).*\bt\s*,\s*t\.messages\s+m/i],
      description: 'chat-session: nested FROM → UNNEST(messages)'
    },
    '21-cleanse-qa-evaluation.sql': {
      patterns: ['UNNEST', 'sections'],
      antiPatterns: [/(?<!--).*\bf\s*,\s*f\.sections\s+s/i],
      description: 'qa-evaluation: nested FROM → UNNEST(sections)'
    },
    '17-cleanse-ivr-session.sql': {
      patterns: ['STRING_AGG'],
      antiPatterns: [/(?<!--).*group_concat\s*\(/i],
      description: 'ivr-session: group_concat → STRING_AGG'
    }
  };

  for (const [scriptName, spec] of Object.entries(scripts)) {
    const candidates = [
      `/workspace/project/bigquery/${scriptName}`,
      `/workspace/project/bigquery/cleanse/${scriptName}`,
    ];
    let filePath = null;
    for (const c of candidates) {
      if (fs.existsSync(c)) { filePath = c; break; }
    }

    check(`${scriptName} exists`, filePath !== null,
      `script not found in repository`);

    if (filePath) {
      const content = fs.readFileSync(filePath, 'utf8');
      const codeLines = content.split('\n').filter(l => !l.trim().startsWith('--'));
      const code = codeLines.join('\n');

      for (const pattern of spec.patterns) {
        check(`${scriptName} contains ${pattern}`,
          new RegExp(pattern, 'i').test(code),
          `${pattern} not found in non-comment code`);
      }

      for (const ap of spec.antiPatterns) {
        check(`${scriptName} no legacy nested syntax`,
          !ap.test(code),
          `legacy Impala nested syntax still present`);
      }
    }
  }

  // Check target tables exist
  const [tables] = await bq.dataset('test').getTables();
  const tableNames = (tables || []).map(t => t.id);

  for (const t of ['ods_chat_session', 'ods_qa_evaluation', 'ods_ivr_session']) {
    check(`${t} table exists in BQ`, tableNames.includes(t),
      'target table not found');
  }

  console.log('');
  console.log(`  RESULT: ${failed === 0 ? 'PASS' : 'FAIL'} (${passed} passed, ${failed} failed)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
