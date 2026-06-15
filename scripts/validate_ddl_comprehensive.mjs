#!/usr/bin/env node
/**
 * validate_ddl_comprehensive.mjs — Offline comprehensive reconciliation of
 * all 115 BigQuery DDL files against the source manifest and Hive DDL.
 *
 * Checks:
 *  (1)  Parse every BQ DDL → columns, partition, cluster, descriptions, object type
 *  (2)  Parse manifest + Hive DDL → expected schema
 *  (3)  Column-by-column parity (name, mapped type, order)
 *  (4)  DECIMAL coverage (7 distinct pairs, X/Y columns)
 *  (5)  68 Hive COMMENTs → BigQuery descriptions
 *  (6)  Identifier legality (reserved words, char sets)
 *  (7)  Nullability (no NOT NULL)
 *  (8)  Partition type legality (no STRING partitions)
 *  (9)  15 views are CREATE VIEW (not TABLE)
 *  (10) Produce validation/reconciliation_evidence.json
 *
 * Run: cd /workspace/project && node scripts/validate_ddl_comprehensive.mjs
 */
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'fs';
import { join, basename } from 'path';

const SRC_DDL_DIR = '/workspace/source/hive/ddl';
const BQ_DDL_DIR  = '/workspace/project/bigquery/ddl';
const MANIFEST    = '/workspace/source/manifests/tables.yaml';
const EVIDENCE_OUT = '/workspace/project/validation/reconciliation_evidence.json';

// ═══════════════════════════════════════════════════════════════════════════════
// BigQuery reserved words (subset most likely to appear as identifiers)
// ═══════════════════════════════════════════════════════════════════════════════
const BQ_RESERVED = new Set([
  'ALL','AND','ANY','ARRAY','AS','ASC','ASSERT_ROWS_MODIFIED','AT','BETWEEN',
  'BY','CASE','CAST','COLLATE','CONTAINS','CREATE','CROSS','CUBE','CURRENT',
  'DEFAULT','DEFINE','DESC','DISTINCT','ELSE','END','ENUM','ESCAPE','EXCEPT',
  'EXCLUDE','EXISTS','EXTRACT','FALSE','FETCH','FOLLOWING','FOR','FROM','FULL',
  'GROUP','GROUPING','GROUPS','HASH','HAVING','IF','IGNORE','IN','INNER',
  'INTERSECT','INTERVAL','INTO','IS','JOIN','LATERAL','LEFT','LIKE','LIMIT',
  'LOOKUP','MERGE','NATURAL','NEW','NO','NOT','NULL','NULLS','OF','ON','OR',
  'ORDER','OUTER','OVER','PARTITION','PRECEDING','PROTO','RANGE','RECURSIVE',
  'RESPECT','RIGHT','ROLLUP','ROWS','SELECT','SET','SOME','STRUCT',
  'TABLESAMPLE','THEN','TO','TREAT','TRUE','UNBOUNDED','UNION','UNNEST',
  'USING','WHEN','WHERE','WINDOW','WITH','WITHIN',
]);

// ═══════════════════════════════════════════════════════════════════════════════
// MANIFEST PARSER
// ═══════════════════════════════════════════════════════════════════════════════
function parseManifest(text) {
  const tables = [];
  const lines = text.split('\n');
  let cur = null, inCols = false;
  for (const line of lines) {
    const t = line.trimEnd();
    const nm = t.match(/^\s{2}- name:\s*(\S+)/);
    if (nm) {
      if (cur) tables.push(cur);
      cur = { name: nm[1], db: null, group: null, format: null, partition: [],
              bucketing: null, columns: [], external: false };
      inCols = false; continue;
    }
    if (!cur) continue;
    const db = t.match(/^\s{4}db:\s*(\S+)/);     if (db) { cur.db = db[1]; continue; }
    const gr = t.match(/^\s{4}group:\s*(\S+)/);   if (gr) { cur.group = gr[1]; continue; }
    const fm = t.match(/^\s{4}format:\s*(\S+)/);  if (fm) { cur.format = fm[1]; continue; }
    const pt = t.match(/^\s{4}partition:\s*\[(.+)\]/);
    if (pt) {
      cur.partition = pt[1].split(',').map(s => {
        const [n, tp] = s.trim().split(':');
        return { name: n.trim(), type: tp ? tp.trim() : 'STRING' };
      });
      continue;
    }
    const bk = t.match(/^\s{4}bucketing:\s*\{\s*by:\s*(\w+),\s*buckets:\s*(\d+)\s*\}/);
    if (bk) { cur.bucketing = { by: bk[1], buckets: +bk[2] }; continue; }
    if (t.match(/^\s{4}columns:\s*$/)) { inCols = true; continue; }
    if (inCols) {
      const cs = t.match(/^\s{6}- (\w[\w.]*:\S+)/);
      if (cs) {
        const p = cs[1].split(':');
        cur.columns.push({ name: p[0], type: p[1],
                           tags: p.slice(2).join(':').split(',').filter(Boolean) });
        continue;
      }
      const cm = t.match(/^\s{6}-\s*\{name:\s*(\w+),\s*type:\s*(.+?)(?:,\s*tags:\s*\[([^\]]*)\])?\s*\}/);
      if (cm) {
        cur.columns.push({ name: cm[1], type: cm[2].replace(/["']/g, '').trim(),
                           tags: cm[3] ? cm[3].split(',').map(s => s.trim()) : [] });
        continue;
      }
      if (t.match(/^\s{4}\w/) || t.match(/^\s{2}-/) || t.match(/^[a-z]/)) inCols = false;
    }
  }
  if (cur) tables.push(cur);
  return tables;
}

function parseManifestViews(text) {
  const views = [];
  const section = text.split(/^views:/m)[1];
  if (!section) return views;
  for (const line of section.split('\n')) {
    const m = line.match(/name:\s*(\w+)/);
    if (m) views.push(m[1]);
  }
  return views;
}

// ═══════════════════════════════════════════════════════════════════════════════
// HIVE COMMENT PARSER
// ═══════════════════════════════════════════════════════════════════════════════
function parseHiveComments(...files) {
  const comments = {};
  for (const fp of files) {
    if (!existsSync(fp)) continue;
    const text = readFileSync(fp, 'utf8');
    let curTable = null;
    for (const line of text.split('\n')) {
      const tm = line.match(/CREATE\s+(?:EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+\S+\.(\S+)\s*\(/i);
      if (tm) { curTable = tm[1]; continue; }
      if (curTable) {
        const cm = line.match(/^\s+(\w+)\s+\S+.*?COMMENT\s+'([^']+)'/);
        if (cm) comments[`${curTable}.${cm[1]}`] = cm[2];
      }
    }
  }
  return comments;
}

// ═══════════════════════════════════════════════════════════════════════════════
// BIGQUERY DDL PARSER (handles \' and '' escapes in OPTIONS)
// ═══════════════════════════════════════════════════════════════════════════════
function parseBqDdl(filepath) {
  if (!existsSync(filepath)) return null;
  const text = readFileSync(filepath, 'utf8');
  const codeLines = text.split('\n').filter(l => !l.trim().startsWith('--'));
  const code = codeLines.join('\n');
  const result = { columns: [], partition: null, cluster: null,
                   tableDescription: null, hasNotNull: false, isView: false,
                   objectType: 'TABLE' };

  if (/CREATE\s+(OR\s+REPLACE\s+)?VIEW/i.test(code)) {
    result.isView = true;
    result.objectType = 'VIEW';
    return result;
  }

  const createMatch = code.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+\S+\s*\(/i);
  if (!createMatch) return result;

  const startIdx = code.indexOf('(', code.indexOf(createMatch[0]));
  let depth = 0, endIdx = -1;
  for (let i = startIdx; i < code.length; i++) {
    if (code[i] === '(') depth++;
    if (code[i] === ')') { depth--; if (depth === 0) { endIdx = i; break; } }
  }
  if (endIdx < 0) return result;

  const colBlock = code.substring(startIdx + 1, endIdx);
  const afterBlock = code.substring(endIdx + 1);

  // Split columns at depth-0 commas with proper escape handling
  const colStrings = [];
  let current = '', parenD = 0, angleD = 0, inStr = false;
  for (let i = 0; i < colBlock.length; i++) {
    const ch = colBlock[i];
    if (ch === "'" && !inStr) { inStr = true; current += ch; continue; }
    if (ch === "'" && inStr) {
      if (i > 0 && colBlock[i - 1] === '\\') { current += ch; continue; }
      if (i + 1 < colBlock.length && colBlock[i + 1] === "'") { current += "''"; i++; continue; }
      inStr = false; current += ch; continue;
    }
    if (inStr) { current += ch; continue; }
    if (ch === '<') angleD++;
    if (ch === '>') angleD--;
    if (ch === '(') parenD++;
    if (ch === ')') parenD--;
    if (ch === ',' && parenD === 0 && angleD === 0) {
      if (current.trim()) colStrings.push(current.trim());
      current = '';
    } else { current += ch; }
  }
  if (current.trim()) colStrings.push(current.trim());

  for (const cs of colStrings) {
    let s = cs, description = null;
    // Extract OPTIONS(description='...')
    const optStart = s.search(/OPTIONS\s*\(/i);
    if (optStart >= 0) {
      const descMatch = s.substring(optStart).match(/OPTIONS\s*\(\s*description\s*=\s*'/i);
      if (descMatch) {
        const dsp = optStart + descMatch.index + descMatch[0].length;
        let desc = '', de = -1;
        for (let j = dsp; j < s.length; j++) {
          if (s[j] === "'" && j > 0 && s[j - 1] === '\\') { desc += "'"; continue; }
          if (s[j] === "'") { if (s[j + 1] === "'") { desc += "'"; j++; continue; } de = j; break; }
          if (s[j] === '\\' && j + 1 < s.length && s[j + 1] === "'") { continue; }
          desc += s[j];
        }
        if (de >= 0) {
          description = desc;
          const foe = s.indexOf(')', de + 1) + 1;
          s = (s.substring(0, optStart) + s.substring(foe)).trim();
        }
      }
    }
    if (s.includes('NOT NULL')) result.hasNotNull = true;
    const colMatch = s.match(/^\s*(\w+)\s+(.+?)\s*$/);
    if (colMatch) {
      result.columns.push({ name: colMatch[1], type: colMatch[2].trim(), description });
    }
  }

  const partMatch = afterBlock.match(/PARTITION\s+BY\s+(.+?)(?:\n|;|$)/im);
  if (partMatch) result.partition = partMatch[1].trim().replace(/;$/, '');
  const clusterMatch = afterBlock.match(/CLUSTER\s+BY\s+([^;\n]+)/i);
  if (clusterMatch) result.cluster = clusterMatch[1].trim().replace(/;$/, '');
  const tblOptMatch = afterBlock.match(/OPTIONS\s*\(\s*description\s*=\s*'([^']*)'\s*\)/i);
  if (tblOptMatch) result.tableDescription = tblOptMatch[1];

  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPE MAPPING
// ═══════════════════════════════════════════════════════════════════════════════
function mapHiveType(t) {
  const u = t.toUpperCase().trim();
  if (u === 'BIGINT') return 'INT64';
  if (u === 'INT') return 'INT64';
  if (u === 'SMALLINT') return 'INT64';
  if (u === 'STRING') return 'STRING';
  if (u === 'BOOLEAN') return 'BOOL';
  if (u === 'DOUBLE') return 'FLOAT64';
  if (u === 'TIMESTAMP') return 'TIMESTAMP';
  if (u === 'DATE') return 'DATE';
  const dm = u.match(/^DECIMAL\((\d+),(\d+)\)$/);
  if (dm) return `NUMERIC(${dm[1]},${dm[2]})`;
  if (u === 'ARRAY<STRING>') return 'ARRAY<STRING>';
  if (u.startsWith('MAP<STRING,STRING>')) return 'JSON';
  if (u.startsWith('ARRAY<STRUCT<')) {
    let inner = u.slice(13, -2);
    inner = inner.replace(/(\w+):(STRING|INT|BIGINT|BOOLEAN|DOUBLE)/gi, (_, n, tp) => {
      const m = { STRING: 'STRING', INT: 'INT64', BIGINT: 'INT64', BOOLEAN: 'BOOL', DOUBLE: 'FLOAT64' };
      return `${n} ${m[tp.toUpperCase()] || tp}`;
    });
    return `ARRAY<STRUCT<${inner}>>`;
  }
  return u;
}

function norm(t) {
  return t.replace(/\s+/g, ' ').replace(/,\s*/g, ', ').trim().toUpperCase();
}

function expectedPartType(name) {
  if (['load_date','feed_date','snapshot_date','event_date','call_date','sched_date'].includes(name)) return 'DATE';
  if (name === 'extract_ts') return 'DATE';
  if (['work_month','period_month','swap_month','event_month'].includes(name)) return 'DATE';
  if (['eff_from_year','date_key','week_start_key'].includes(name)) return 'INT64';
  if (['channel','site_code','client_code'].includes(name)) return 'STRING';
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════════════════════
const manifestText = readFileSync(MANIFEST, 'utf8');
const tables = parseManifest(manifestText);
const manifestViews = parseManifestViews(manifestText);
const hiveComments = parseHiveComments(
  join(SRC_DDL_DIR, '02-staging-sqoop-mirrors.hql'),
  join(SRC_DDL_DIR, '03-staging-delta-feeds.hql'),
  join(SRC_DDL_DIR, '04-staging-file-feeds.hql'),
  join(SRC_DDL_DIR, '05-ods-cleanse.hql'),
  join(SRC_DDL_DIR, '06-ods-delta-scd2.hql'),
  join(SRC_DDL_DIR, '07-ods-acid.hql'),
  join(SRC_DDL_DIR, '08-dm-tables.hql'),
);

console.log(`Parsed ${tables.length} tables, ${manifestViews.length} views from manifest`);
console.log(`Found ${Object.keys(hiveComments).length} Hive column COMMENTs\n`);

// ── Evidence accumulator ────────────────────────────────────────────────────
const evidence = {
  timestamp: new Date().toISOString(),
  summary: {},
  tables: {},
  views: {},
  checks: {
    column_parity: { pass: 0, fail: 0, details: [] },
    decimal: { pairs_found: [], columns_checked: 0, total_decimal_cols: 0 },
    comments: { preserved: 0, missing: 0, details: [] },
    identifiers: { total: 0, bad_start: [], illegal_chars: [], reserved_collisions: [] },
    nullability: { total_cols: 0, violations: [] },
    partition_types: { total: 0, string_partitions: [], illegal_types: [] },
    views: { total: 0, correct: 0, wrong_type: [] },
  },
};

let totalColsReconciled = 0;
let totalTablesReconciled = 0;
let totalIssues = 0;

const decimalPairsFound = new Set();
const allDecimalCols = [];
let totalIdentifiers = 0;
let totalColumns = 0;

// ═══════════════════════════════════════════════════════════════════════════════
// CHECK TABLES (1)–(8)
// ═══════════════════════════════════════════════════════════════════════════════
for (const tbl of tables) {
  const bqDir = tbl.db === 'staging' ? 'staging' : tbl.db === 'ods' ? 'ods' : 'dm';
  const bqFile = join(BQ_DDL_DIR, bqDir, `${tbl.name}.sql`);

  const tblEvidence = {
    name: tbl.name, dataset: bqDir, file_exists: false,
    expected_col_count: 0, actual_col_count: 0,
    columns: [], issues: [],
  };

  if (!existsSync(bqFile)) {
    tblEvidence.issues.push({ check: 'FILE_EXISTS', detail: `Missing ${bqFile}` });
    totalIssues++;
    evidence.tables[tbl.name] = tblEvidence;
    continue;
  }
  tblEvidence.file_exists = true;

  const bq = parseBqDdl(bqFile);
  if (!bq || bq.columns.length === 0) {
    tblEvidence.issues.push({ check: 'PARSE', detail: '0 columns parsed' });
    totalIssues++;
    evidence.tables[tbl.name] = tblEvidence;
    continue;
  }

  const bqMap = {};
  for (const c of bq.columns) bqMap[c.name] = c;

  // Build expected columns: data columns + inlined partition columns
  const expectedCols = [
    ...tbl.columns.map(c => ({ name: c.name, type: c.type, tags: c.tags || [] })),
    ...tbl.partition.map(p => ({
      name: p.name === 'extract_ts' ? 'extract_date' : p.name,
      type: p.type, tags: ['partition'], origName: p.name,
    })),
  ];

  tblEvidence.expected_col_count = expectedCols.length;
  tblEvidence.actual_col_count = bq.columns.length;

  // (3) Column count
  if (bq.columns.length !== expectedCols.length) {
    tblEvidence.issues.push({ check: 'COL_COUNT',
      detail: `expected ${expectedCols.length} got ${bq.columns.length}` });
    totalIssues++;
  }

  // (3) Column-by-column parity: name, order, mapped type
  let colsMatch = true;
  for (let i = 0; i < expectedCols.length; i++) {
    const exp = expectedCols[i];
    const act = i < bq.columns.length ? bq.columns[i] : null;
    const bqName = exp.name;

    const colEvidence = {
      position: i, expected_name: bqName,
      actual_name: act ? act.name : null,
      expected_type: null, actual_type: act ? act.type : null,
      description: act ? act.description : null,
      status: 'PASS',
    };

    // Name/order
    if (!act || act.name !== bqName) {
      colEvidence.status = 'FAIL';
      colEvidence.issue = `name mismatch at position ${i}: expected '${bqName}' got '${act ? act.name : 'MISSING'}'`;
      colsMatch = false;
      totalIssues++;
    }

    // Type mapping for data columns (not partition)
    if (act && act.name === bqName && !exp.tags.includes('partition')) {
      const expType = norm(mapHiveType(exp.type));
      const actType = norm(act.type);
      colEvidence.expected_type = mapHiveType(exp.type);
      if (expType !== actType) {
        colEvidence.status = 'FAIL';
        colEvidence.issue = `type mismatch: expected ${mapHiveType(exp.type)} got ${act.type}`;
        colsMatch = false;
        totalIssues++;
      }
    }

    // Type mapping for partition columns
    if (act && act.name === bqName && exp.tags.includes('partition')) {
      const origName = exp.origName || exp.name;
      const expPartType = expectedPartType(origName);
      colEvidence.expected_type = expPartType;
      if (expPartType && act.type !== expPartType) {
        colEvidence.status = 'FAIL';
        colEvidence.issue = `partition type: expected ${expPartType} got ${act.type}`;
        colsMatch = false;
        totalIssues++;
      }
    }

    // (7) Nullability — no NOT NULL
    totalColumns++;

    // (6) Identifier check
    if (act) {
      totalIdentifiers++;
      const id = act.name;
      if (!/^[a-zA-Z_]/.test(id)) {
        evidence.checks.identifiers.bad_start.push(`${tbl.name}.${id}`);
        totalIssues++;
      }
      if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(id)) {
        evidence.checks.identifiers.illegal_chars.push(`${tbl.name}.${id}`);
        totalIssues++;
      }
      if (BQ_RESERVED.has(id.toUpperCase())) {
        evidence.checks.identifiers.reserved_collisions.push(`${tbl.name}.${id}`);
      }
    }

    tblEvidence.columns.push(colEvidence);
  }

  // (6) Table name identifier check
  totalIdentifiers++;
  if (!/^[a-zA-Z_]/.test(tbl.name)) {
    evidence.checks.identifiers.bad_start.push(tbl.name);
    totalIssues++;
  }
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(tbl.name)) {
    evidence.checks.identifiers.illegal_chars.push(tbl.name);
    totalIssues++;
  }
  if (BQ_RESERVED.has(tbl.name.toUpperCase())) {
    evidence.checks.identifiers.reserved_collisions.push(tbl.name);
  }

  if (colsMatch && bq.columns.length === expectedCols.length) {
    totalColsReconciled += expectedCols.length;
    totalTablesReconciled++;
    evidence.checks.column_parity.pass++;
  } else {
    evidence.checks.column_parity.fail++;
    evidence.checks.column_parity.details.push(tbl.name);
  }

  // (4) DECIMAL columns
  for (const col of tbl.columns) {
    const dm = col.type.match(/DECIMAL\((\d+),(\d+)\)/i);
    if (dm) {
      allDecimalCols.push(`${tbl.name}.${col.name}`);
      evidence.checks.decimal.total_decimal_cols++;
      const bc = bqMap[col.name];
      if (bc) {
        const exp = `NUMERIC(${dm[1]},${dm[2]})`;
        if (norm(bc.type) === norm(exp)) {
          decimalPairsFound.add(exp);
          evidence.checks.decimal.columns_checked++;
        }
      }
    }
  }

  // (5) Comment preservation
  for (const col of tbl.columns) {
    const key = `${tbl.name}.${col.name}`;
    const hc = hiveComments[key];
    if (!hc) continue;
    const bc = bqMap[col.name];
    if (bc && bc.description && bc.description.length > 0) {
      evidence.checks.comments.preserved++;
    } else {
      evidence.checks.comments.missing++;
      evidence.checks.comments.details.push(key);
      totalIssues++;
    }
  }

  // (7) Nullability
  if (bq.hasNotNull) {
    evidence.checks.nullability.violations.push(tbl.name);
    tblEvidence.issues.push({ check: 'NOT_NULL', detail: 'contains NOT NULL constraint' });
    totalIssues++;
  }

  // (8) Partition type legality
  if (bq.partition) {
    for (const pc of tbl.partition) {
      const bqName = pc.name === 'extract_ts' ? 'extract_date' : pc.name;
      const bc = bqMap[bqName];
      evidence.checks.partition_types.total++;
      if (bc && bc.type === 'STRING' && bq.partition.includes(bqName)) {
        evidence.checks.partition_types.string_partitions.push(`${tbl.name}.${bqName}`);
        totalIssues++;
      }
      if (bc && !['DATE', 'TIMESTAMP', 'DATETIME', 'INT64', 'STRING'].includes(bc.type) &&
          bq.partition.includes(bqName)) {
        evidence.checks.partition_types.illegal_types.push(`${tbl.name}.${bqName}: ${bc.type}`);
        totalIssues++;
      }
    }
  }

  evidence.tables[tbl.name] = tblEvidence;
}

evidence.checks.nullability.total_cols = totalColumns;
evidence.checks.identifiers.total = totalIdentifiers;
evidence.checks.decimal.pairs_found = [...decimalPairsFound].sort();

// ═══════════════════════════════════════════════════════════════════════════════
// CHECK VIEWS (9)
// ═══════════════════════════════════════════════════════════════════════════════
for (const vn of manifestViews) {
  const bqFile = join(BQ_DDL_DIR, 'dm', `${vn}.sql`);
  evidence.checks.views.total++;

  const vEvidence = { name: vn, file_exists: false, object_type: null, status: 'PASS' };

  if (!existsSync(bqFile)) {
    vEvidence.status = 'FAIL';
    vEvidence.issue = 'file missing';
    evidence.checks.views.wrong_type.push(vn);
    totalIssues++;
  } else {
    vEvidence.file_exists = true;
    const bq = parseBqDdl(bqFile);
    vEvidence.object_type = bq ? bq.objectType : 'UNKNOWN';
    if (bq && bq.isView) {
      evidence.checks.views.correct++;
    } else {
      vEvidence.status = 'FAIL';
      vEvidence.issue = `expected VIEW got ${bq ? bq.objectType : 'UNPARSEABLE'}`;
      evidence.checks.views.wrong_type.push(vn);
      totalIssues++;
    }

    // Identifier check for view names
    totalIdentifiers++;
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(vn)) {
      evidence.checks.identifiers.illegal_chars.push(vn);
      totalIssues++;
    }
  }

  evidence.views[vn] = vEvidence;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY + COVERAGE LINES
// ═══════════════════════════════════════════════════════════════════════════════
const totalExpectedCols = tables.reduce((s, t) => s + t.columns.length + t.partition.length, 0);

evidence.summary = {
  tables_parsed: tables.length,
  views_parsed: manifestViews.length,
  hive_comments: Object.keys(hiveComments).length,
  total_issues: totalIssues,
  columns_reconciled: totalColsReconciled,
  tables_reconciled: totalTablesReconciled,
  decimal_cols_checked: evidence.checks.decimal.columns_checked,
  decimal_pairs_found: evidence.checks.decimal.pairs_found.length,
  comments_preserved: evidence.checks.comments.preserved,
  comments_missing: evidence.checks.comments.missing,
  identifiers_checked: totalIdentifiers,
  nullability_violations: evidence.checks.nullability.violations.length,
  partition_string_violations: evidence.checks.partition_types.string_partitions.length,
  views_correct: evidence.checks.views.correct,
  views_wrong: evidence.checks.views.wrong_type.length,
};

// ── Print results ─────────────────────────────────────────────────────────────
console.log('═'.repeat(70));
console.log('COMPREHENSIVE DDL RECONCILIATION');
console.log('═'.repeat(70));
console.log('');

// (3) Column parity
const colIcon = totalTablesReconciled === tables.length ? '✅' : '❌';
console.log(`${colIcon} reconciled ${totalColsReconciled}/${totalExpectedCols} columns across ${totalTablesReconciled}/${tables.length} tables`);
if (evidence.checks.column_parity.fail > 0) {
  console.log(`   FAILED tables: ${evidence.checks.column_parity.details.join(', ')}`);
}

// (4) DECIMAL
const decIcon = decimalPairsFound.size === 7 ? '✅' : '❌';
console.log(`${decIcon} checked ${evidence.checks.decimal.columns_checked}/${evidence.checks.decimal.total_decimal_cols} DECIMAL columns, ${decimalPairsFound.size}/7 distinct pairs`);

// (5) Comments
const totalComments = Object.keys(hiveComments).length;
const cmtIcon = evidence.checks.comments.missing === 0 ? '✅' : '❌';
console.log(`${cmtIcon} preserved ${evidence.checks.comments.preserved}/${totalComments} comments`);
if (evidence.checks.comments.missing > 0) {
  console.log(`   MISSING: ${evidence.checks.comments.details.join(', ')}`);
}

// (6) Identifiers
const idBad = evidence.checks.identifiers.bad_start.length +
              evidence.checks.identifiers.illegal_chars.length;
const idIcon = idBad === 0 ? '✅' : '❌';
const idWarn = evidence.checks.identifiers.reserved_collisions.length;
console.log(`${idIcon} checked ${totalIdentifiers}/${totalIdentifiers} identifiers (${idBad} illegal, ${idWarn} reserved-word collisions)`);

// (7) Nullability
const nullViol = evidence.checks.nullability.violations.length;
const nullIcon = nullViol === 0 ? '✅' : '❌';
console.log(`${nullIcon} checked ${totalColumns}/${totalColumns} columns for nullability (${nullViol} NOT NULL violations)`);
if (nullViol > 0) {
  console.log(`   VIOLATIONS: ${evidence.checks.nullability.violations.join(', ')}`);
}

// (8) Partition types
const partStr = evidence.checks.partition_types.string_partitions.length;
const partIcon = partStr === 0 ? '✅' : '❌';
console.log(`${partIcon} checked ${evidence.checks.partition_types.total} partition columns (${partStr} STRING partition violations)`);

// (9) Views
const viewIcon = evidence.checks.views.correct === manifestViews.length ? '✅' : '❌';
console.log(`${viewIcon} verified ${evidence.checks.views.correct}/${manifestViews.length} views are CREATE VIEW (not TABLE)`);
if (evidence.checks.views.wrong_type.length > 0) {
  console.log(`   WRONG TYPE: ${evidence.checks.views.wrong_type.join(', ')}`);
}

console.log('');
console.log('─'.repeat(70));
if (totalIssues === 0) {
  console.log('RESULT: ✅ ALL CHECKS PASSED — 0 issues');
} else {
  console.log(`RESULT: ❌ ${totalIssues} issues found`);
}
console.log('─'.repeat(70));

// (10) Write evidence JSON
writeFileSync(EVIDENCE_OUT, JSON.stringify(evidence, null, 2), 'utf8');
console.log(`\nEvidence written to: ${EVIDENCE_OUT}`);
console.log(`  ${Object.keys(evidence.tables).length} table records`);
console.log(`  ${Object.keys(evidence.views).length} view records`);
console.log(`  ${evidence.summary.columns_reconciled} column-level reconciliation records`);

process.exit(totalIssues > 0 ? 1 : 0);
