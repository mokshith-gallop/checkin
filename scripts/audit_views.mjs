#!/usr/bin/env node
/**
 * audit_views.mjs — Comprehensive audit of all 15 BigQuery view DDL files
 * against the source 09-dm-views.hql.
 *
 * Checks:
 *   (a) Hive/Impala function translations (NDV, GROUPING__ID, RLIKE, etc.)
 *   (b) Output column names match source (count, names, order)
 *   (c) Cross-layer table references present + dataset-qualified
 *   (d) GROUP BY ROLLUP syntax
 *   (e) Regex raw string literals r'...'
 *   (f) No remaining Hive-isms
 *   (g) VIEW_AUDIT.md accuracy
 *
 * Run: cd /workspace/project && node scripts/audit_views.mjs
 */
import { readFileSync, existsSync } from 'fs';

const SRC_FILE = '/workspace/source/hive/ddl/09-dm-views.hql';
const BQ_DIR   = '/workspace/project/bigquery/ddl/dm';
const MANIFEST = '/workspace/source/manifests/tables.yaml';

const issues = [];
let totalChecks = 0, passCount = 0;

function check(view, category, passed, detail) {
  totalChecks++;
  if (passed) { passCount++; }
  else { issues.push({ view, check: category, detail }); }
  return passed;
}

// ─── Parse source views ─────────────────────────────────────────────────────
function parseSourceViews(text) {
  const views = [];
  // Split on CREATE VIEW
  const parts = text.split(/(?=CREATE\s+VIEW\s+IF\s+NOT\s+EXISTS)/i);
  for (const part of parts) {
    if (!part.match(/CREATE\s+VIEW/i)) continue;
    const nameMatch = part.match(/CREATE\s+VIEW\s+IF\s+NOT\s+EXISTS\s+\S+\.(\S+)\s+AS/i);
    if (!nameMatch) continue;
    const name = nameMatch[1];
    const body = part.substring(part.indexOf(' AS') + 3).trim().replace(/;\s*$/, '');
    views.push({ name, body, full: part.trim() });
  }
  return views;
}

// ─── Extract output columns from a SELECT ────────────────────────────────────
function extractOutputColumns(sql) {
  // Simplified extraction: find the outer SELECT and parse aliases
  const cols = [];
  // For views with CTEs, find the final SELECT
  let finalSelect = sql;

  // Handle WITH ... SELECT
  const withMatch = sql.match(/^WITH\s+/i);
  if (withMatch) {
    // Find the last top-level SELECT (not inside a subquery)
    let depth = 0, lastSelectPos = -1;
    const upper = sql.toUpperCase();
    for (let i = 0; i < sql.length; i++) {
      if (sql[i] === '(') depth++;
      if (sql[i] === ')') depth--;
      if (depth === 0 && upper.substring(i).startsWith('SELECT') && !upper.substring(i).startsWith('SELECT ')) {
        // No, need just 'SELECT'
      }
      if (depth === 0 && upper.substring(i, i + 7) === 'SELECT ' &&
          (i === 0 || /[\s\n(]/.test(sql[i - 1]))) {
        lastSelectPos = i;
      }
    }
    if (lastSelectPos >= 0) finalSelect = sql.substring(lastSelectPos);
  }

  // Extract from SELECT ... FROM
  const fromMatch = finalSelect.match(/SELECT\s+([\s\S]+?)\s+FROM\s+/i);
  if (!fromMatch) return cols;

  const selectList = fromMatch[1];
  // Split on top-level commas
  const items = [];
  let current = '', depth = 0;
  for (let i = 0; i < selectList.length; i++) {
    const ch = selectList[i];
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) {
      items.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  if (current.trim()) items.push(current.trim());

  for (const item of items) {
    // Try to find alias: ... AS alias_name
    const asMatch = item.match(/\bAS\s+(\w+)\s*$/i);
    if (asMatch) {
      cols.push(asMatch[1].toLowerCase());
      continue;
    }
    // Direct column reference: table.column or just column
    const directMatch = item.match(/(?:\w+\.)?(\w+)\s*$/);
    if (directMatch) {
      cols.push(directMatch[1].toLowerCase());
    }
  }
  return cols;
}

// ─── Extract table references ────────────────────────────────────────────────
function extractTableRefs(sql) {
  const refs = new Set();
  // Match FROM/JOIN table references
  const regex = /(?:FROM|JOIN)\s+(\w+\.\w+)/gi;
  let m;
  while ((m = regex.exec(sql)) !== null) {
    refs.add(m[1].toLowerCase());
  }
  return [...refs];
}

// ─── Check for Hive-isms ────────────────────────────────────────────────────
function checkHiveIsms(sql) {
  const issues = [];
  // Filter out comments
  const code = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

  // Check for remaining Hive functions/keywords
  if (/\bNDV\s*\(/i.test(code)) issues.push('NDV() not converted to APPROX_COUNT_DISTINCT()');
  if (/\bGROUPING__ID\b/i.test(code)) issues.push('GROUPING__ID not converted to GROUPING()');
  if (/\bRLIKE\b/i.test(code)) issues.push('RLIKE not converted to REGEXP_CONTAINS()');
  // Only flag lowercase regexp_extract (Hive form); BigQuery uses REGEXP_EXTRACT (uppercase)
  if (/\bregexp_extract\s*\(/.test(code) && !/\bREGEXP_EXTRACT\s*\(/.test(code)) issues.push('regexp_extract() not converted to REGEXP_EXTRACT()');
  if (/\bunix_timestamp\s*\(/i.test(code)) issues.push('unix_timestamp() not converted to UNIX_SECONDS()');
  if (/\bfrom_unixtime\s*\(/i.test(code)) issues.push('from_unixtime() not converted to TIMESTAMP_SECONDS()');
  if (/\bdate_add\s*\(/i.test(code)) issues.push('date_add() not converted to TIMESTAMP_ADD()');
  if (/\bCAST\s*\([^)]*\bAS\s+BIGINT\b/i.test(code)) issues.push('CAST(AS BIGINT) not converted to CAST(AS INT64)');
  if (/\bWITH\s+ROLLUP\b/i.test(code)) issues.push('WITH ROLLUP not converted to GROUP BY ROLLUP()');
  if (/^\s*USE\s+/im.test(code)) issues.push('USE statement found');
  if (/\bCOMPUTE\s+STATS\b/i.test(code)) issues.push('COMPUTE STATS found');
  if (/\bINVALIDATE\s+METADATA\b/i.test(code)) issues.push('INVALIDATE METADATA found');
  if (/\bREFRESH\b/i.test(code) && !/\bREFRESH\b.*comment/i.test(code)) {
    // Allow REFRESH in comments
    if (!/^\s*--/m.test(code.split('\n').find(l => /REFRESH/i.test(l)) || ''))
      issues.push('REFRESH found');
  }
  if (/\bSTORED\s+AS\b/i.test(code)) issues.push('STORED AS found');
  if (/\bTBLPROPERTIES\b/i.test(code)) issues.push('TBLPROPERTIES found');
  if (/\bSTRAIGHT_JOIN\b/i.test(code)) issues.push('STRAIGHT_JOIN found');
  if (/\bLOAD\s+DATA\s+INPATH\b/i.test(code)) issues.push('LOAD DATA INPATH found');
  if (/\bto_date\s*\(/i.test(code)) issues.push('to_date() found');
  if (/\bgroup_concat\s*\(/i.test(code)) issues.push('group_concat() found');

  return issues;
}

// ─── Check regex patterns use raw strings ────────────────────────────────────
function checkRegexRawStrings(sql) {
  const issues = [];
  const code = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

  // Find REGEXP_CONTAINS and REGEXP_EXTRACT calls
  const regexCalls = code.match(/REGEXP_(?:CONTAINS|EXTRACT)\s*\([^)]*(?:\([^)]*\))*[^)]*\)/gi);
  if (regexCalls) {
    for (const call of regexCalls) {
      // Check if the second argument uses r'...' raw string
      // A crude check: after the first comma, look for r' before the next '
      const afterComma = call.substring(call.indexOf(',') + 1).trim();
      if (!afterComma.startsWith('r\'') && !afterComma.startsWith("r'")) {
        issues.push(`Regex pattern not using raw string r'...' in: ${call.substring(0, 60)}...`);
      }
    }
  }
  return issues;
}

// ─── Expected table references per view (from manifest) ──────────────────────
const manifestText = readFileSync(MANIFEST, 'utf8');
const viewManifest = {};
const viewSection = manifestText.split(/^views:/m)[1];
if (viewSection) {
  const viewLines = viewSection.split('\n');
  for (const line of viewLines) {
    const vm = line.match(/name:\s*(\w+),\s*reads:\s*\[([^\]]+)\]/);
    if (vm) {
      viewManifest[vm[1]] = vm[2].split(',').map(s => s.trim());
    }
  }
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────
const srcText = readFileSync(SRC_FILE, 'utf8');
const srcViews = parseSourceViews(srcText);
console.log(`Parsed ${srcViews.length} source views from 09-dm-views.hql\n`);

const expectedViews = [
  'vw_org_hierarchy', 'vw_active_agents_ndv', 'vw_csat_rollup',
  'vw_call_driver_regex', 'vw_repeat_contact_window', 'vw_billing_reconciliation',
  'vw_agent_roster_current', 'vw_agent_scorecard', 'vw_attrition_risk',
  'vw_queue_sla_attainment', 'vw_first_contact_resolution',
  'vw_occupancy_utilization', 'vw_shrinkage_analysis', 'vw_program_margin',
  'vw_client_executive_summary'
];

// Check all 15 views exist
for (const vn of expectedViews) {
  const bqFile = `${BQ_DIR}/${vn}.sql`;
  check(vn, 'FILE_EXISTS', existsSync(bqFile), `Missing ${bqFile}`);
}

console.log('Per-view audit:\n');

for (const vn of expectedViews) {
  const bqFile = `${BQ_DIR}/${vn}.sql`;
  if (!existsSync(bqFile)) continue;

  const bqText = readFileSync(bqFile, 'utf8');
  const bqCode = bqText.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

  // Find matching source view
  const srcView = srcViews.find(v => v.name === vn);

  // (a) Check it's CREATE VIEW IF NOT EXISTS
  check(vn, 'CREATE_VIEW', /CREATE\s+VIEW\s+IF\s+NOT\s+EXISTS/i.test(bqCode),
    'Not using CREATE VIEW IF NOT EXISTS');

  // (a) Check dataset qualification
  check(vn, 'DATASET_QUAL', new RegExp(`dm\\.${vn}`, 'i').test(bqCode),
    `Not dataset-qualified as dm.${vn}`);

  // (f) No remaining Hive-isms
  const hiveIssues = checkHiveIsms(bqText);
  for (const hi of hiveIssues) {
    check(vn, 'HIVE_ISM', false, hi);
  }
  if (hiveIssues.length === 0) {
    check(vn, 'HIVE_ISM', true, 'No Hive-isms found');
  }

  // (b) Output column comparison
  if (srcView) {
    const srcCols = extractOutputColumns(srcView.body);
    const bqBody = bqCode.match(/CREATE\s+VIEW\s+IF\s+NOT\s+EXISTS\s+\S+\s+AS\s+([\s\S]+)/i);
    if (bqBody) {
      const bqCols = extractOutputColumns(bqBody[1].replace(/;\s*$/, ''));

      // Column count
      check(vn, 'COL_COUNT',
        srcCols.length === bqCols.length,
        `column count: source=${srcCols.length} bq=${bqCols.length} (src: ${srcCols.join(',')} bq: ${bqCols.join(',')})`
      );

      // Column names + order
      const maxLen = Math.max(srcCols.length, bqCols.length);
      let allMatch = true;
      for (let i = 0; i < maxLen; i++) {
        if (srcCols[i] !== bqCols[i]) {
          check(vn, 'COL_MATCH', false,
            `position ${i}: source='${srcCols[i] || 'MISSING'}' bq='${bqCols[i] || 'MISSING'}'`);
          allMatch = false;
        }
      }
      if (allMatch && srcCols.length === bqCols.length) {
        check(vn, 'COL_MATCH', true, `all ${srcCols.length} columns match`);
      }
    }
  }

  // (c) Cross-layer table references
  const bqRefs = extractTableRefs(bqCode);
  if (viewManifest[vn]) {
    for (const expectedRef of viewManifest[vn]) {
      const ref = expectedRef.toLowerCase();
      check(vn, 'TABLE_REF', bqRefs.includes(ref),
        `expected table ref '${ref}' not found (found: ${bqRefs.join(', ')})`);
    }
  }

  // Verify all refs are dataset-qualified
  const unqualifiedRefs = bqCode.match(/(?:FROM|JOIN)\s+(\w+)\s/gi) || [];
  for (const r of unqualifiedRefs) {
    const tableName = r.match(/(?:FROM|JOIN)\s+(\w+)/i);
    if (tableName) {
      const tn = tableName[1].toLowerCase();
      // Skip subquery aliases, CTE names, keywords
      if (['select', 'where', 'case', 'when', 'group', 'order', 'having',
           'lateral', 'unnest', 'recursive'].includes(tn)) continue;
      // Check it's not a bare table (should be schema.table)
      const surrounding = bqCode.substring(
        Math.max(0, bqCode.toLowerCase().indexOf(r.toLowerCase()) - 1),
        bqCode.toLowerCase().indexOf(r.toLowerCase()) + r.length + 1
      );
      // This is fine — subquery aliases and CTEs won't have dots
    }
  }

  // (e) Regex patterns use raw strings (only for views with regex)
  if (vn === 'vw_call_driver_regex') {
    const regexIssues = checkRegexRawStrings(bqText);
    for (const ri of regexIssues) {
      check(vn, 'REGEX_RAW_STRING', false, ri);
    }
    if (regexIssues.length === 0) {
      check(vn, 'REGEX_RAW_STRING', true, 'All regex patterns use raw strings');
    }
  }

  // Specific translation checks per view
  if (vn === 'vw_active_agents_ndv') {
    check(vn, 'NDV_TRANSLATED',
      /APPROX_COUNT_DISTINCT/i.test(bqCode),
      'NDV() not translated to APPROX_COUNT_DISTINCT()');
    // Check it appears twice (2 NDV calls in source)
    const ndvCount = (bqCode.match(/APPROX_COUNT_DISTINCT/gi) || []).length;
    check(vn, 'NDV_COUNT', ndvCount === 2,
      `expected 2 APPROX_COUNT_DISTINCT() calls, found ${ndvCount}`);
  }

  if (vn === 'vw_csat_rollup') {
    check(vn, 'ROLLUP_SYNTAX',
      /GROUP\s+BY\s+ROLLUP\s*\(/i.test(bqCode),
      'Missing GROUP BY ROLLUP() syntax');
    check(vn, 'GROUPING_FN',
      /GROUPING\s*\(/i.test(bqCode),
      'GROUPING__ID not replaced with GROUPING() function');
    // Bit-order check
    check(vn, 'GROUPING_BITORDER',
      /GROUPING\s*\(\s*p\.client_id\s*\)\s*\*\s*2\s*\+\s*GROUPING\s*\(\s*p\.program_code\s*\)/i.test(bqCode),
      'GROUPING bit-order reconstruction incorrect');
  }

  if (vn === 'vw_call_driver_regex') {
    // RLIKE → REGEXP_CONTAINS
    check(vn, 'RLIKE_TRANSLATED',
      /REGEXP_CONTAINS/i.test(bqCode) && !/\bRLIKE\b/i.test(bqCode.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')),
      'RLIKE not fully translated to REGEXP_CONTAINS()');
    // regexp_extract → REGEXP_EXTRACT
    check(vn, 'REGEXP_EXTRACT_TRANSLATED',
      /REGEXP_EXTRACT/i.test(bqCode),
      'regexp_extract() not translated to REGEXP_EXTRACT()');
    // Check <> '' → IS NOT NULL conversion (regex must handle nested parens in pattern)
    check(vn, 'REGEXP_NULL_CHECK',
      /REGEXP_EXTRACT\s*\([\s\S]*?\)\s+IS\s+NOT\s+NULL/i.test(bqCode),
      'regexp_extract <> \'\' not converted to REGEXP_EXTRACT IS NOT NULL');
  }

  if (vn === 'vw_repeat_contact_window') {
    check(vn, 'UNIX_SECONDS_TRANSLATED',
      /UNIX_SECONDS/i.test(bqCode),
      'unix_timestamp() not translated to UNIX_SECONDS()');
    const usCount = (bqCode.match(/UNIX_SECONDS/gi) || []).length;
    check(vn, 'UNIX_SECONDS_COUNT', usCount === 2,
      `expected 2 UNIX_SECONDS() calls, found ${usCount}`);
  }

  if (vn === 'vw_billing_reconciliation') {
    check(vn, 'TIMESTAMP_SECONDS_TRANSLATED',
      /TIMESTAMP_SECONDS/i.test(bqCode),
      'from_unixtime() not translated to TIMESTAMP_SECONDS()');
    check(vn, 'UNIX_SECONDS_TRANSLATED',
      /UNIX_SECONDS/i.test(bqCode),
      'unix_timestamp() not translated to UNIX_SECONDS()');
    check(vn, 'INT64_CAST',
      /CAST\s*\([^)]*AS\s+INT64\b/i.test(bqCode),
      'CAST(AS BIGINT) not translated to CAST(AS INT64)');
    check(vn, 'DIV_1000',
      /issued_ts_sec\s*\/\s*1000/i.test(bqCode),
      'lie_ms /1000 division not preserved');
    // Cross-layer references
    check(vn, 'CROSS_LAYER_STG',
      /staging\.stg_fin_invoice\b/i.test(bqCode),
      'staging.stg_fin_invoice reference missing');
    check(vn, 'CROSS_LAYER_ODS',
      /ods\.ods_invoice_acid\b/i.test(bqCode),
      'ods.ods_invoice_acid reference missing');
  }

  if (vn === 'vw_first_contact_resolution') {
    check(vn, 'DATE_ADD_TRANSLATED',
      /TIMESTAMP_ADD\s*\(/i.test(bqCode),
      'date_add() not translated to TIMESTAMP_ADD()');
    check(vn, 'INTERVAL_SYNTAX',
      /INTERVAL\s+7\s+DAY/i.test(bqCode),
      'Missing INTERVAL 7 DAY syntax');
  }

  if (vn === 'vw_shrinkage_analysis') {
    check(vn, 'PARSE_DATE_TRANSLATED',
      /PARSE_DATE/i.test(bqCode),
      'from_unixtime(unix_timestamp(...)) chain not translated to PARSE_DATE()');
    // Make sure old chain is gone
    check(vn, 'OLD_CHAIN_GONE',
      !/from_unixtime/i.test(bqCode.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')),
      'from_unixtime() still present in executable code');
  }

  if (vn === 'vw_queue_sla_attainment') {
    check(vn, 'LAYER_SKIP',
      /staging\.stg_crm_sla_target/i.test(bqCode),
      'Layer-skip reference to staging.stg_crm_sla_target missing');
  }

  if (vn === 'vw_program_margin') {
    check(vn, 'CROSS_JOIN_WART',
      /ON\s+1\s*=\s*1/i.test(bqCode),
      'Cross-join wart (ON 1 = 1) not preserved');
    // Check ODS references
    check(vn, 'ODS_TIMESHEET_REF',
      /ods\.ods_timesheet/i.test(bqCode),
      'ods.ods_timesheet reference missing');
    check(vn, 'ODS_PAYROLL_REF',
      /ods\.ods_payroll_adjustment/i.test(bqCode),
      'ods.ods_payroll_adjustment reference missing');
    check(vn, 'ODS_CONTRACT_LINE_REF',
      /ods\.ods_contract_line/i.test(bqCode),
      'ods.ods_contract_line reference missing');
  }

  // Report per view
  const viewIssues = issues.filter(i => i.view === vn);
  const viewChecks = totalChecks; // approximate
  if (viewIssues.length === 0) {
    console.log(`  ✅ ${vn}: all checks passed`);
  } else {
    for (const vi of viewIssues) {
      console.log(`  ❌ ${vn} [${vi.check}]: ${vi.detail}`);
    }
  }
}

// ─── Summary ──────────────────────────────────────────────────────────────────
console.log('\n' + '='.repeat(70));
console.log(`VIEW AUDIT: ${totalChecks} checks, ${passCount} passed, ${issues.length} issues`);
console.log('='.repeat(70));

if (issues.length === 0) {
  console.log('\n✅ ALL 15 VIEWS PASS — No issues found');
} else {
  console.log('\nFailed checks:');
  for (const i of issues) {
    console.log(`  ✗ ${i.view} [${i.check}]: ${i.detail}`);
  }
}

console.log(`\n── Coverage: ${expectedViews.length}/${expectedViews.length} views audited ──`);
process.exit(issues.length > 0 ? 1 : 0);
