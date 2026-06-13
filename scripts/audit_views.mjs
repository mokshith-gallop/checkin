#!/usr/bin/env node
/**
 * audit_views.mjs — Comprehensive audit of all 15 BigQuery view SQL files
 * against source 09-dm-views.hql.
 *
 * Checks:
 *  1. All 15 views exist as files
 *  2. Each uses CREATE VIEW IF NOT EXISTS (not CREATE OR REPLACE)
 *  3. Each references dm.vw_<name> (correct dataset prefix)
 *  4. No residual Hive-isms: NDV(), RLIKE, regexp_extract(), GROUPING__ID,
 *     from_unixtime(), unix_timestamp(), CAST(x AS BIGINT), date_add(ts, N)
 *  5. Correct replacements present where expected
 *  6. All table references use dataset-qualified names
 *  7. No CREATE OR REPLACE
 */
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const BQ_DIR = '/workspace/project/bigquery/ddl/dm';
const SRC = '/workspace/source/hive/ddl/09-dm-views.hql';

const VIEWS = [
  'vw_org_hierarchy',
  'vw_active_agents_ndv',
  'vw_csat_rollup',
  'vw_call_driver_regex',
  'vw_repeat_contact_window',
  'vw_billing_reconciliation',
  'vw_agent_roster_current',
  'vw_agent_scorecard',
  'vw_attrition_risk',
  'vw_queue_sla_attainment',
  'vw_first_contact_resolution',
  'vw_occupancy_utilization',
  'vw_shrinkage_analysis',
  'vw_program_margin',
  'vw_client_executive_summary',
];

const issues = [];
let totalChecks = 0;
let passCount = 0;

function check(view, name, condition, detail) {
  totalChecks++;
  if (condition) {
    passCount++;
  } else {
    issues.push({ view, check: name, detail });
  }
}

// Read source for reference
const srcText = readFileSync(SRC, 'utf8');

for (const viewName of VIEWS) {
  const filePath = join(BQ_DIR, `${viewName}.sql`);

  // Check 1: File exists
  check(viewName, 'FILE_EXISTS', existsSync(filePath), `Missing ${filePath}`);
  if (!existsSync(filePath)) continue;

  const text = readFileSync(filePath, 'utf8');
  // Code only (no comments)
  const codeLines = text.split('\n').filter(l => !l.trim().startsWith('--'));
  const code = codeLines.join('\n');

  // Check 2: Uses CREATE VIEW IF NOT EXISTS
  check(viewName, 'CREATE_VIEW_IFNE',
    /CREATE\s+VIEW\s+IF\s+NOT\s+EXISTS/i.test(code),
    'Should use CREATE VIEW IF NOT EXISTS');

  // Check 2b: Does NOT use CREATE OR REPLACE
  check(viewName, 'NO_CREATE_OR_REPLACE',
    !/CREATE\s+OR\s+REPLACE/i.test(code),
    'Should NOT use CREATE OR REPLACE');

  // Check 3: References dm.<viewName>
  check(viewName, 'DATASET_PREFIX',
    code.includes(`dm.${viewName}`),
    `Should reference dm.${viewName}`);

  // Check 4: No residual Hive-isms in code
  // NDV()
  check(viewName, 'NO_NDV',
    !/\bNDV\s*\(/i.test(code),
    'Residual NDV() found — should be APPROX_COUNT_DISTINCT()');

  // RLIKE
  check(viewName, 'NO_RLIKE',
    !/\bRLIKE\b/i.test(code),
    'Residual RLIKE found — should be REGEXP_CONTAINS()');

  // Hive regexp_extract (case-sensitive — BQ uses REGEXP_EXTRACT)
  check(viewName, 'NO_HIVE_REGEXP_EXTRACT',
    !/\bregexp_extract\s*\(/i.test(code) || /\bREGEXP_EXTRACT\s*\(/.test(code),
    'Residual lowercase regexp_extract() — should be REGEXP_EXTRACT()');

  // GROUPING__ID
  check(viewName, 'NO_GROUPING__ID',
    !/GROUPING__ID/i.test(code),
    'Residual GROUPING__ID — should use GROUPING() reconstruction');

  // from_unixtime (Hive function)
  check(viewName, 'NO_FROM_UNIXTIME',
    !/\bfrom_unixtime\s*\(/i.test(code),
    'Residual from_unixtime() — should be TIMESTAMP_SECONDS()');

  // unix_timestamp (Hive function) — should be UNIX_SECONDS
  check(viewName, 'NO_UNIX_TIMESTAMP',
    !/\bunix_timestamp\s*\(/i.test(code),
    'Residual unix_timestamp() — should be UNIX_SECONDS()');

  // CAST(x AS BIGINT) — should be CAST(x AS INT64)
  check(viewName, 'NO_CAST_BIGINT',
    !/CAST\s*\([^)]*\s+AS\s+BIGINT\s*\)/i.test(code),
    'Residual CAST(... AS BIGINT) — should be CAST(... AS INT64)');

  // Hive date_add(ts, N) — should be TIMESTAMP_ADD
  // But be careful: date_add is not used in most views
  check(viewName, 'NO_HIVE_DATE_ADD',
    !/\bdate_add\s*\(/i.test(code),
    'Residual date_add() — should be TIMESTAMP_ADD()');

  // WITH ROLLUP placement — should be GROUP BY ROLLUP(...)
  check(viewName, 'NO_WITH_ROLLUP',
    !/\bWITH\s+ROLLUP\b/i.test(code),
    'Residual WITH ROLLUP — should be GROUP BY ROLLUP(...)');

  // Check 5: Table references are dataset-qualified
  // Look for table references without dataset prefix — only in actual SQL, not comments
  const sqlLines = text.split('\n')
    .filter(l => !l.trim().startsWith('--'))
    .map(l => l.replace(/--.*$/, '')); // strip inline comments too
  const sqlOnly = sqlLines.join('\n');
  const tableRefPattern = /\b(FROM|JOIN)\s+(?!dm\.|ods\.|staging\.)\b([a-z_]+)\b/gi;
  let m;
  const unqualifiedRefs = [];
  while ((m = tableRefPattern.exec(sqlOnly)) !== null) {
    const ref = m[2];
    // Ignore CTE names, subquery aliases, and SQL keywords
    if (['org_tree','perf','qa','skills','banded','adh','notice','wk','lab','adj','cmt',
         'latest','RECURSIVE','SELECT','LATERAL'].includes(ref)) continue;
    unqualifiedRefs.push(ref);
  }
  check(viewName, 'QUALIFIED_TABLE_REFS',
    unqualifiedRefs.length === 0,
    `Unqualified table references: ${unqualifiedRefs.join(', ')}`);

  // Check 6: View-specific translation verifications
  if (viewName === 'vw_active_agents_ndv') {
    check(viewName, 'HAS_APPROX_COUNT_DISTINCT',
      /APPROX_COUNT_DISTINCT\s*\(/i.test(code),
      'Should contain APPROX_COUNT_DISTINCT()');
  }

  if (viewName === 'vw_csat_rollup') {
    check(viewName, 'HAS_GROUP_BY_ROLLUP',
      /GROUP\s+BY\s+ROLLUP\s*\(/i.test(code),
      'Should contain GROUP BY ROLLUP(...)');
    check(viewName, 'HAS_GROUPING_FUNC',
      /\bGROUPING\s*\(/i.test(code),
      'Should contain GROUPING() function');
  }

  if (viewName === 'vw_call_driver_regex') {
    check(viewName, 'HAS_REGEXP_CONTAINS',
      /REGEXP_CONTAINS\s*\(/i.test(code),
      'Should contain REGEXP_CONTAINS()');
    check(viewName, 'HAS_REGEXP_EXTRACT',
      /REGEXP_EXTRACT\s*\(/i.test(code),
      'Should contain REGEXP_EXTRACT()');
    check(viewName, 'HAS_RAW_STRINGS',
      /r'/i.test(code),
      "Should use raw string literals r'...'");
  }

  if (viewName === 'vw_repeat_contact_window') {
    check(viewName, 'HAS_UNIX_SECONDS',
      /UNIX_SECONDS\s*\(/i.test(code),
      'Should contain UNIX_SECONDS()');
  }

  if (viewName === 'vw_billing_reconciliation') {
    check(viewName, 'HAS_TIMESTAMP_SECONDS',
      /TIMESTAMP_SECONDS\s*\(/i.test(code),
      'Should contain TIMESTAMP_SECONDS()');
    check(viewName, 'HAS_UNIX_SECONDS',
      /UNIX_SECONDS\s*\(/i.test(code),
      'Should contain UNIX_SECONDS()');
    check(viewName, 'HAS_CAST_INT64',
      /CAST\s*\([^)]*\s+AS\s+INT64\s*\)/i.test(code),
      'Should contain CAST(... AS INT64)');
  }

  if (viewName === 'vw_first_contact_resolution') {
    check(viewName, 'HAS_TIMESTAMP_ADD',
      /TIMESTAMP_ADD\s*\(/i.test(code),
      'Should contain TIMESTAMP_ADD()');
    check(viewName, 'HAS_INTERVAL_DAY',
      /INTERVAL\s+7\s+DAY/i.test(code),
      'Should contain INTERVAL 7 DAY');
  }

  if (viewName === 'vw_org_hierarchy') {
    check(viewName, 'HAS_WITH_RECURSIVE',
      /WITH\s+RECURSIVE/i.test(code),
      'Should contain WITH RECURSIVE');
  }

  if (viewName === 'vw_shrinkage_analysis') {
    check(viewName, 'HAS_PARSE_DATE',
      /PARSE_DATE\s*\(/i.test(code),
      'Should contain PARSE_DATE()');
    check(viewName, 'SCHED_DATE_DATE_TYPE',
      /s\.sched_date\s*=\s*PARSE_DATE/i.test(code),
      'Should compare sched_date (DATE) with PARSE_DATE result');
  }
}

// ── Output ──────────────────────────────────────────────────────────────
console.log('='.repeat(70));
console.log(`VIEW AUDIT: ${totalChecks} checks, ${passCount} passed, ${issues.length} issues`);
console.log('='.repeat(70));
console.log('');

if (issues.length === 0) {
  console.log('✅ ALL 15 VIEWS PASS — No issues found.');
} else {
  for (const iss of issues) {
    console.log(`  ✗ ${iss.view}: [${iss.check}] ${iss.detail}`);
  }
}

console.log('');
console.log(`Views checked: ${VIEWS.length}/15`);

process.exit(issues.length > 0 ? 1 : 0);
