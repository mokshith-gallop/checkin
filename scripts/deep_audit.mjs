#!/usr/bin/env node
/**
 * deep_audit.mjs — Exhaustive column-by-column audit of all 100 BigQuery
 * table DDL files against manifests/tables.yaml and Hive source DDL.
 *
 * Covers all checks (a)–(i) from the step description:
 *   (a) column count = source data cols + inlined partition cols
 *   (b) column names + order match
 *   (c) type mappings follow canonical map
 *   (d) all 68 Hive COMMENTs preserved as OPTIONS(description=...)
 *   (e) epoch columns: staging=INT64, ODS/DM=TIMESTAMP
 *   (f) lie_ms columns carry millis warning
 *   (g) partition columns correctly inlined + type-changed
 *   (h) DECIMAL columns: correct 7 distinct precision/scale pairs
 *   (i) complex types: ARRAY<STRUCT>, ARRAY<STRING>, MAP→JSON
 *
 * Run: cd /workspace/project && node scripts/deep_audit.mjs
 */
import { readFileSync, existsSync, readdirSync } from 'fs';
import { join } from 'path';

const SRC_DDL_DIR = '/workspace/source/hive/ddl';
const BQ_DDL_DIR  = '/workspace/project/bigquery/ddl';
const MANIFEST    = '/workspace/source/manifests/tables.yaml';

// ─── Minimal manifest parser ──────────────────────────────────────────────────
function parseManifest(text) {
  const tables = [];
  const lines = text.split('\n');
  let cur = null;
  let inCols = false;

  for (const line of lines) {
    const t = line.trimEnd();
    const nm = t.match(/^\s{2}- name:\s*(\S+)/);
    if (nm) {
      if (cur) tables.push(cur);
      cur = { name: nm[1], db: null, group: null, format: null, partition: [], bucketing: null, columns: [], external: false };
      inCols = false;
      continue;
    }
    if (!cur) continue;
    const db = t.match(/^\s{4}db:\s*(\S+)/);        if (db) { cur.db = db[1]; continue; }
    const gr = t.match(/^\s{4}group:\s*(\S+)/);      if (gr) { cur.group = gr[1]; continue; }
    const fm = t.match(/^\s{4}format:\s*(\S+)/);     if (fm) { cur.format = fm[1]; continue; }
    const ext = t.match(/^\s{4}external:\s*(true|false)/); if (ext) { cur.external = ext[1] === 'true'; continue; }
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
        cur.columns.push({ name: p[0], type: p[1], tags: p.slice(2).join(':').split(',').filter(Boolean) });
        continue;
      }
      const cm = t.match(/^\s{6}-\s*\{name:\s*(\w+),\s*type:\s*(.+?)(?:,\s*tags:\s*\[([^\]]*)\])?\s*\}/);
      if (cm) {
        cur.columns.push({ name: cm[1], type: cm[2].replace(/["']/g, '').trim(), tags: cm[3] ? cm[3].split(',').map(s => s.trim()) : [] });
        continue;
      }
      if (t.match(/^\s{4}\w/) || t.match(/^\s{2}-/) || t.match(/^[a-z]/)) inCols = false;
    }
  }
  if (cur) tables.push(cur);
  return tables;
}

// ─── Parse Hive COMMENTs from source DDL ──────────────────────────────────────
function parseHiveComments(filepath) {
  if (!existsSync(filepath)) return {};
  const text = readFileSync(filepath, 'utf8');
  const comments = {};
  let curTable = null;
  for (const line of text.split('\n')) {
    const tm = line.match(/CREATE\s+(?:EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+\S+\.(\S+)\s*\(/i);
    if (tm) { curTable = tm[1]; continue; }
    if (curTable) {
      const cm = line.match(/^\s+(\w+)\s+\S+.*?COMMENT\s+'([^']+)'/);
      if (cm) comments[`${curTable}.${cm[1]}`] = cm[2];
    }
  }
  return comments;
}

// ─── Robust BQ DDL column parser that handles escaped quotes in OPTIONS ──────
function parseBqDdl(filepath) {
  if (!existsSync(filepath)) return null;
  const text = readFileSync(filepath, 'utf8');
  const codeLines = text.split('\n').filter(l => !l.trim().startsWith('--'));
  const code = codeLines.join('\n');
  const result = { columns: [], partition: null, cluster: null, tableDescription: null, hasNotNull: false, isView: false };

  // Check if it's a view
  if (/CREATE\s+(OR\s+REPLACE\s+)?VIEW/i.test(code)) { result.isView = true; return result; }

  const createMatch = code.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+\S+\s*\(/i);
  if (!createMatch) return result;

  // Find the matching close paren for the column list
  const startIdx = code.indexOf('(', code.indexOf(createMatch[0]));
  let depth = 0, endIdx = -1;
  for (let i = startIdx; i < code.length; i++) {
    if (code[i] === '(') depth++;
    if (code[i] === ')') { depth--; if (depth === 0) { endIdx = i; break; } }
  }
  if (endIdx < 0) return result;

  const colBlock = code.substring(startIdx + 1, endIdx);
  const afterBlock = code.substring(endIdx + 1);

  // Split columns at depth-0 commas using a proper state machine that handles
  // both single quotes (including \' escape sequences AND '' escape sequences)
  // and angle brackets for complex types.
  const colStrings = [];
  let current = '', parenDepth = 0, angleBracketDepth = 0, inStr = false;
  for (let i = 0; i < colBlock.length; i++) {
    const ch = colBlock[i];

    // String literal handling with proper escape support
    if (ch === "'" && !inStr) {
      inStr = true;
      current += ch;
      continue;
    }
    if (ch === "'" && inStr) {
      // Check for \' backslash escape
      if (i > 0 && colBlock[i - 1] === '\\') {
        current += ch;
        continue;
      }
      // Check for '' double-quote escape
      if (i + 1 < colBlock.length && colBlock[i + 1] === "'") {
        current += "''";
        i++;
        continue;
      }
      inStr = false;
      current += ch;
      continue;
    }
    if (inStr) { current += ch; continue; }

    // Track nesting
    if (ch === '<') angleBracketDepth++;
    if (ch === '>') angleBracketDepth--;
    if (ch === '(') parenDepth++;
    if (ch === ')') parenDepth--;

    if (ch === ',' && parenDepth === 0 && angleBracketDepth === 0) {
      if (current.trim()) colStrings.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  if (current.trim()) colStrings.push(current.trim());

  // Parse each column definition
  for (const cs of colStrings) {
    let s = cs;
    let description = null;

    // Extract OPTIONS(description='...') — handle \' and '' escapes
    const optStart = s.search(/OPTIONS\s*\(/i);
    if (optStart >= 0) {
      const descMatch = s.substring(optStart).match(/OPTIONS\s*\(\s*description\s*=\s*'/i);
      if (descMatch) {
        const descStartPos = optStart + descMatch.index + descMatch[0].length;
        let descEnd = -1;
        let desc = '';
        for (let j = descStartPos; j < s.length; j++) {
          if (s[j] === "'" && s[j - 1] === '\\') {
            desc += "'";
            continue;
          }
          if (s[j] === "'") {
            if (s[j + 1] === "'") { desc += "'"; j++; continue; }
            descEnd = j;
            break;
          }
          if (s[j] === '\\' && s[j + 1] === "'") { continue; }
          desc += s[j];
        }
        if (descEnd >= 0) {
          description = desc;
          // Remove the full OPTIONS clause from the type string
          const fullOptEnd = s.indexOf(')', descEnd + 1) + 1;
          s = (s.substring(0, optStart) + s.substring(fullOptEnd)).trim();
        }
      }
    }

    if (s.includes('NOT NULL')) result.hasNotNull = true;

    const colMatch = s.match(/^\s*(\w+)\s+(.+?)\s*$/);
    if (colMatch) {
      result.columns.push({ name: colMatch[1], type: colMatch[2].trim(), description });
    }
  }

  // Parse PARTITION BY
  const partMatch = afterBlock.match(/PARTITION\s+BY\s+(.+?)(?:\n|;|$)/im);
  if (partMatch) result.partition = partMatch[1].trim().replace(/;$/, '');

  // Parse CLUSTER BY
  const clusterMatch = afterBlock.match(/CLUSTER\s+BY\s+([^;\n]+)/i);
  if (clusterMatch) result.cluster = clusterMatch[1].trim().replace(/;$/, '');

  // Table-level OPTIONS
  const tblOptMatch = afterBlock.match(/OPTIONS\s*\(\s*description\s*=\s*'([^']*)'\s*\)/i);
  if (tblOptMatch) result.tableDescription = tblOptMatch[1];

  return result;
}

// ─── Type mapping ─────────────────────────────────────────────────────────────
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

function normalizeType(t) {
  return t.replace(/\s+/g, ' ').replace(/,\s*/g, ', ').trim().toUpperCase();
}

// ─── Expected partition type ──────────────────────────────────────────────────
function expectedPartType(name) {
  if (['load_date', 'feed_date', 'snapshot_date', 'event_date', 'call_date', 'sched_date'].includes(name)) return 'DATE';
  if (name === 'extract_ts') return 'DATE'; // renamed to extract_date
  if (['work_month', 'period_month', 'swap_month', 'event_month'].includes(name)) return 'DATE';
  if (['eff_from_year', 'date_key', 'week_start_key'].includes(name)) return 'INT64';
  if (['channel', 'site_code', 'client_code'].includes(name)) return 'STRING';
  return null;
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────
const tables = parseManifest(readFileSync(MANIFEST, 'utf8'));
console.log(`Parsed ${tables.length} tables from manifest\n`);

const hiveComments = {};
for (const f of [
  '02-staging-sqoop-mirrors.hql', '03-staging-delta-feeds.hql',
  '04-staging-file-feeds.hql', '05-ods-cleanse.hql',
  '06-ods-delta-scd2.hql', '07-ods-acid.hql', '08-dm-tables.hql'
]) {
  Object.assign(hiveComments, parseHiveComments(join(SRC_DDL_DIR, f)));
}
console.log(`Found ${Object.keys(hiveComments).length} Hive column COMMENTs\n`);

const issues = [];
let totalChecks = 0, passCount = 0;
const decimalPairsFound = new Set();
const allDecimalCols = [];

function check(table, category, passed, detail) {
  totalChecks++;
  if (passed) { passCount++; }
  else { issues.push({ table, check: category, detail }); }
  return passed;
}

for (const tbl of tables) {
  const bqDir = tbl.db === 'staging' ? 'staging' : tbl.db === 'ods' ? 'ods' : 'dm';
  const bqFile = join(BQ_DDL_DIR, bqDir, `${tbl.name}.sql`);

  // (a) File exists
  if (!check(tbl.name, 'FILE_EXISTS', existsSync(bqFile), `Missing ${bqFile}`)) continue;

  const bq = parseBqDdl(bqFile);
  if (!bq || bq.columns.length === 0) {
    check(tbl.name, 'PARSE', false, '0 columns parsed');
    continue;
  }

  const bqMap = {};
  for (const c of bq.columns) bqMap[c.name] = c;

  // Build expected column list: data columns + inlined partition columns
  const expectedCols = [
    ...tbl.columns.map(c => c.name),
    ...tbl.partition.map(p => p.name === 'extract_ts' ? 'extract_date' : p.name)
  ];

  // (a) Column count
  check(tbl.name, 'COL_COUNT',
    bq.columns.length === expectedCols.length,
    `expected ${expectedCols.length} got ${bq.columns.length}`
  );

  // (b) Column order
  for (let i = 0; i < expectedCols.length; i++) {
    if (i < bq.columns.length) {
      check(tbl.name, 'COL_ORDER',
        bq.columns[i].name === expectedCols[i],
        `position ${i}: expected '${expectedCols[i]}' got '${bq.columns[i].name}'`
      );
    }
  }

  // (b) Check no extra columns
  for (const bc of bq.columns) {
    check(tbl.name, 'COL_EXTRA',
      expectedCols.includes(bc.name),
      `unexpected column '${bc.name}'`
    );
  }

  // (c) Type mapping for data columns
  for (const col of tbl.columns) {
    const bc = bqMap[col.name];
    if (!bc) continue;
    const expType = normalizeType(mapHiveType(col.type));
    const actType = normalizeType(bc.type);
    check(tbl.name, 'TYPE_MAP',
      expType === actType,
      `${col.name}: expected ${mapHiveType(col.type)} got ${bc.type}`
    );
  }

  // (g) Partition column types
  for (const pc of tbl.partition) {
    const bqName = pc.name === 'extract_ts' ? 'extract_date' : pc.name;
    const bc = bqMap[bqName];
    if (!bc) {
      check(tbl.name, 'PART_COL_EXISTS', false, `partition column '${bqName}' not found`);
      continue;
    }
    const exp = expectedPartType(pc.name);
    if (exp) {
      check(tbl.name, 'PART_TYPE',
        bc.type === exp,
        `${bqName}: expected ${exp} got ${bc.type}`
      );
    }
  }

  // (g) Multi-column partition demotion
  if (tbl.partition.length > 1) {
    // Determine which column should be demoted
    let demoted;
    if (tbl.partition[0].name === 'client_code') demoted = 'client_code'; // file feeds: client_code demoted
    else if (tbl.partition[1].name === 'site_code') demoted = 'site_code';
    else if (tbl.partition[1].name === 'channel') demoted = 'channel';
    else demoted = tbl.partition[1].name;

    check(tbl.name, 'MULTI_PART_CLUSTER',
      bq.cluster && bq.cluster.toLowerCase().includes(demoted.toLowerCase()),
      `demoted partition column '${demoted}' not in CLUSTER BY (got: ${bq.cluster || 'none'})`
    );
  }

  // Bucketing → CLUSTER BY
  if (tbl.bucketing) {
    check(tbl.name, 'BUCKET_CLUSTER',
      bq.cluster && bq.cluster.toLowerCase().includes(tbl.bucketing.by.toLowerCase()),
      `bucketed column '${tbl.bucketing.by}' not in CLUSTER BY (got: ${bq.cluster || 'none'})`
    );
  }

  // (d) Hive COMMENT preservation
  for (const col of tbl.columns) {
    const key = `${tbl.name}.${col.name}`;
    const hc = hiveComments[key];
    if (!hc) continue;
    const bc = bqMap[col.name];
    if (!bc) continue;
    check(tbl.name, 'COMMENT_PRESERVED',
      bc.description != null && bc.description.length > 0,
      `${col.name}: Hive COMMENT '${hc}' has no OPTIONS(description) in BigQuery`
    );
  }

  // (e) Epoch columns in staging must be INT64
  for (const col of tbl.columns) {
    const tags = col.tags || [];
    const isEpoch = tags.some(t => ['epoch_sec', 'epoch_ms', 'lie_ms'].includes(t));
    const isOraStr = tags.includes('ora_str');

    if (tbl.db === 'staging' && isEpoch) {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'EPOCH_STG_INT64',
        bc.type === 'INT64',
        `${col.name}: staging epoch should be INT64 got ${bc.type}`
      );
    }
    if (tbl.db === 'staging' && isOraStr) {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'ORA_STR_STRING',
        bc.type === 'STRING',
        `${col.name}: staging ora_str should be STRING got ${bc.type}`
      );
    }
  }

  // (e) TIMESTAMP columns in ODS/DM must be TIMESTAMP
  if (['ods', 'dm'].includes(tbl.db)) {
    for (const col of tbl.columns) {
      if (col.type === 'TIMESTAMP') {
        const bc = bqMap[col.name];
        if (!bc) continue;
        check(tbl.name, 'ODS_TIMESTAMP',
          bc.type === 'TIMESTAMP',
          `${col.name}: ODS/DM TIMESTAMP should be TIMESTAMP got ${bc.type}`
        );
      }
    }
  }

  // (f) lie_ms columns must have millis warning
  for (const col of tbl.columns) {
    const tags = col.tags || [];
    if (tags.includes('lie_ms')) {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'LIE_MS_DESC',
        bc.description != null && /millis/i.test(bc.description),
        `${col.name}: lie_ms column missing millis warning in description (got: ${bc.description || 'none'})`
      );
    }
  }

  // (h) DECIMAL columns
  for (const col of tbl.columns) {
    const dm = col.type.match(/DECIMAL\((\d+),(\d+)\)/i);
    if (dm) {
      allDecimalCols.push({ table: tbl.name, col: col.name, p: +dm[1], s: +dm[2] });
      const bc = bqMap[col.name];
      if (bc) {
        const exp = `NUMERIC(${dm[1]},${dm[2]})`;
        if (normalizeType(bc.type) === normalizeType(exp)) {
          decimalPairsFound.add(`NUMERIC(${dm[1]},${dm[2]})`);
        }
      }
    }
  }

  // ACID tables: no NOT NULL, has CLUSTER BY
  if (tbl.group === 'acid') {
    check(tbl.name, 'ACID_NOT_NULL',
      !bq.hasNotNull,
      'contains NOT NULL constraint (MERGE-incompatible)'
    );
    check(tbl.name, 'ACID_HAS_CLUSTER',
      bq.cluster != null,
      'ACID table missing CLUSTER BY'
    );
  }

  // SCD-2 surrogate keys
  if (tbl.group === 'scd2') {
    const sk = tbl.columns.find(c => c.name.endsWith('_history_id'));
    if (sk) {
      const bc = bqMap[sk.name];
      check(tbl.name, 'SCD2_KEY_DESC',
        bc && bc.description && bc.description.includes('TO_HEX(MD5('),
        `${sk.name}: SCD-2 key missing TO_HEX(MD5(...)) in description (desc: ${bc?.description || 'none'})`
      );
    }
  }

  // Format-specific tables need table description
  if (['TEXTFILE_PIPE', 'TEXTFILE_CSV', 'JSON', 'REGEX', 'SEQUENCEFILE', 'RCFILE'].includes(tbl.format)) {
    check(tbl.name, 'FORMAT_TBL_DESC',
      bq.tableDescription != null,
      `format=${tbl.format} missing table-level OPTIONS(description)`
    );
  }

  // (i) Complex type specific checks
  for (const col of tbl.columns) {
    if (col.type.startsWith('ARRAY<STRUCT<')) {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'COMPLEX_ARRAY_STRUCT',
        normalizeType(bc.type).startsWith('ARRAY<STRUCT<'),
        `${col.name}: expected ARRAY<STRUCT<...>> got ${bc.type}`
      );
    }
    if (col.type === 'ARRAY<STRING>') {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'COMPLEX_ARRAY_STRING',
        normalizeType(bc.type) === 'ARRAY<STRING>',
        `${col.name}: expected ARRAY<STRING> got ${bc.type}`
      );
    }
    if (col.type.startsWith('MAP<STRING,STRING>')) {
      const bc = bqMap[col.name];
      if (!bc) continue;
      check(tbl.name, 'COMPLEX_MAP_JSON',
        bc.type === 'JSON',
        `${col.name}: expected JSON got ${bc.type}`
      );
    }
  }

  // No STRING partitions (partition type must be DATE, TIMESTAMP, DATETIME, or INT64 for range)
  if (bq.partition) {
    const partStr = bq.partition;
    // Check if the partition references a column that's STRING
    for (const pc of tbl.partition) {
      const bqName = pc.name === 'extract_ts' ? 'extract_date' : pc.name;
      const bc = bqMap[bqName];
      if (bc && bc.type === 'STRING' && partStr.includes(bqName)) {
        check(tbl.name, 'PART_NOT_STRING',
          false,
          `partition column '${bqName}' is STRING (BigQuery requires DATE/TIMESTAMP/INT64 range)`
        );
      }
    }
  }
}

// ─── Reporting ────────────────────────────────────────────────────────────────
console.log('='.repeat(70));
console.log(`AUDIT: ${totalChecks} checks, ${passCount} passed, ${issues.length} issues`);
console.log('='.repeat(70));

if (issues.length === 0) {
  console.log('\n✅ ALL CHECKS PASSED');
} else {
  const byCheck = {};
  for (const i of issues) {
    (byCheck[i.check] || (byCheck[i.check] = [])).push(i);
  }
  for (const [c, items] of Object.entries(byCheck).sort()) {
    console.log(`\n── ${c} (${items.length}) ──`);
    for (const i of items) console.log(`  ✗ ${i.table}: ${i.detail}`);
  }
}

console.log(`\n── DECIMAL: ${allDecimalCols.length} columns, ${decimalPairsFound.size} distinct pairs: ${[...decimalPairsFound].sort().join(', ')} ──`);

// Check that all 7 expected pairs are present
const expectedPairs = ['NUMERIC(14,2)', 'NUMERIC(12,4)', 'NUMERIC(12,2)', 'NUMERIC(10,4)', 'NUMERIC(8,2)', 'NUMERIC(7,2)', 'NUMERIC(5,2)'];
const missingPairs = expectedPairs.filter(p => !decimalPairsFound.has(p));
if (missingPairs.length > 0) {
  console.log(`  ⚠ Missing DECIMAL pairs: ${missingPairs.join(', ')}`);
}

// Comment coverage
const totalComments = Object.keys(hiveComments).length;
const commentIssues = issues.filter(i => i.check === 'COMMENT_PRESERVED').length;
console.log(`\n── COMMENTs: ${totalComments - commentIssues}/${totalComments} Hive COMMENTs preserved ──`);

process.exit(issues.length > 0 ? 1 : 0);
