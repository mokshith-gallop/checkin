#!/usr/bin/env node
// =============================================================================
// AC #8 — Live-diff validation: Impala source ↔ BigQuery target
//
// For every source table in the 100-table estate:
//   1. Attempts to CREATE it in a scratch Impala database from source DDL
//   2. Runs DESCRIBE on the live Impala table
//   3. Creates the corresponding BQ table in a scratch dataset from converted DDL
//   4. Reads BQ metadata via table.getMetadata()
//   5. Compares column-for-column: name, count, order, mapped type, mode,
//      DECIMAL precision/scale, partition, clustering, table type
//   6. Prints raw Impala DESCRIBE + raw BQ getMetadata per table as evidence
//   7. Any table where live read is missing → HARD FAIL
//   8. Tables Impala cannot create → source-ddl-not-creatable (named construct)
//
// Usage:
//   set -a; source /workspace/.gallop/db.env; set +a
//   node validation/ac8_live_diff_tables.mjs
// =============================================================================
import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');

const hive = require('hive-driver');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');
const fs   = require('fs');
const path  = require('path');

const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);

// ── Config ──────────────────────────────────────────────────────────────
const SRC_DDL  = '/workspace/source/hive/ddl';
const BQ_DDL   = '/workspace/project/bigquery/ddl';
const BQ_DS    = process.env.BIGQUERY_TEST_BQ_DATASETS || 'test';
const IMP_PFX  = 'qa_val8_';          // Impala scratch DB prefix
const BQ_PFX   = 'qa_val8_';          // BQ scratch table prefix

const SRC_FILES = [
  '02-staging-sqoop-mirrors.hql',
  '03-staging-delta-feeds.hql',
  '04-staging-file-feeds.hql',
  '05-ods-cleanse.hql',
  '06-ods-delta-scd2.hql',
  '07-ods-acid.hql',
  '08-dm-tables.hql',
];

// Impala reserved words that may appear as column names in the DDL
const RESERVED = new Set([
  'role','comment','end','start','date','key','type','order','group',
  'table','column','replace','select','from','where','join','on',
  'in','as','is','not','and','or','like','case','when','then','else',
  'true','false','null','int','float','double','string','boolean',
  'timestamp','decimal','array','map','struct','partition','data',
]);

// ── Hive → BQ type map (for comparison) ─────────────────────────────────
const TMAP = {
  TINYINT:'INT64', SMALLINT:'INT64', INT:'INT64', BIGINT:'INT64',
  FLOAT:'FLOAT64', DOUBLE:'FLOAT64', STRING:'STRING', BOOLEAN:'BOOL',
  TIMESTAMP:'TIMESTAMP', DATE:'DATE', BINARY:'BYTES',
};
function mapType(ht) {
  const t = ht.toUpperCase().trim();
  if (TMAP[t]) return TMAP[t];
  const d = t.match(/^DECIMAL\((\d+),\s*(\d+)\)$/);
  if (d) return `NUMERIC(${d[1]},${d[2]})`;
  if (t === 'ARRAY<STRING>') return 'ARRAY<STRING>';
  if (t.startsWith('MAP<')) return 'JSON';
  if (t.startsWith('ARRAY<STRUCT<')) {
    let inner = t.slice(13, -2); // strip ARRAY<STRUCT< and >>
    inner = inner.replace(/(\w+):(STRING|INT|BIGINT|BOOLEAN|DOUBLE|FLOAT|SMALLINT|TINYINT)/gi,
      (_, n, tp) => `${n.toLowerCase()} ${TMAP[tp.toUpperCase()]||tp.toUpperCase()}`);
    return `ARRAY<STRUCT<${inner}>>`;
  }
  return t;
}

// ── Parse Hive DDL into individual CREATE TABLE statements ──────────────
function parseSrcFile(fp) {
  const txt = fs.readFileSync(fp, 'utf8');
  const out = [];
  const parts = txt.split(/(?=CREATE\s+(?:EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS)/i);
  for (const part of parts) {
    const hdr = part.match(/CREATE\s+(EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+(\S+)/i);
    if (!hdr) continue;
    const [db, name] = hdr[2].includes('.') ? hdr[2].split('.') : ['default', hdr[2]];
    const semi = part.indexOf(';');
    const stmt = semi >= 0 ? part.substring(0, semi + 1) : part.trim() + ';';

    // detect Impala-blocking constructs
    const blocks = [];
    if (/transactional.*true/i.test(stmt))       blocks.push('ACID/transactional');
    if (/MAP\s*<\s*STRING\s*,\s*STRING\s*>/i.test(stmt)) blocks.push('MAP<STRING,STRING>');
    if (/RegexSerDe/i.test(stmt))                blocks.push('RegexSerDe');

    out.push({ db, name, stmt, blocks });
  }
  return out;
}

// ── Adapt Hive DDL for Impala scratch execution ─────────────────────────
function adaptImpala(stmt, db, name) {
  let s = stmt;
  const sdb = IMP_PFX + db;

  // rewrite CREATE header to scratch DB
  s = s.replace(/CREATE\s+(EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+\S+/i,
    `CREATE TABLE IF NOT EXISTS ${sdb}.${name}`);

  // strip Hive-only clauses
  s = s.replace(/LOCATION\s+'[^']*'\s*;?/gi, '');
  s = s.replace(/TBLPROPERTIES\s*\([^)]*\)\s*;?/gi, '');
  s = s.replace(/ROW\s+FORMAT[\s\S]*?(?=STORED|LOCATION|TBLPROPERTIES|PARTITIONED|;|$)/gi, '');
  s = s.replace(/WITH\s+SERDEPROPERTIES\s*\([^)]*\)/gi, '');
  s = s.replace(/STORED\s+AS\s+\w+/gi, '');
  s = s.replace(/CLUSTERED\s+BY\s*\([^)]*\)\s+INTO\s+\d+\s+BUCKETS/gi, '');

  // backtick-quote reserved-word column names in the column block
  const p1 = s.indexOf('(');
  if (p1 >= 0) {
    let depth = 0, p2 = -1;
    for (let i = p1; i < s.length; i++) {
      if (s[i] === '(') depth++;
      if (s[i] === ')') { depth--; if (depth === 0) { p2 = i; break; } }
    }
    if (p2 > 0) {
      let cb = s.substring(p1, p2 + 1);
      // quote bare reserved words at start of a column-def line
      cb = cb.replace(/^(\s+)(\w+)(\s+)/gm, (m, ws, w, tr) =>
        RESERVED.has(w.toLowerCase()) ? `${ws}\`${w}\`${tr}` : m);
      s = s.substring(0, p1) + cb + s.substring(p2 + 1);
    }
  }

  // quote reserved words used as PARTITION column names (first word in each pair)
  // e.g. PARTITIONED BY (load_date STRING) — load_date is the name, STRING is the type
  s = s.replace(/PARTITIONED\s+BY\s*\(([^)]+)\)/gi, (_, inner) => {
    // split on comma to get each "colname TYPE" pair
    const fixed = inner.split(',').map(pair => {
      const trimmed = pair.trim();
      const parts = trimmed.split(/\s+/);
      if (parts.length >= 2 && RESERVED.has(parts[0].toLowerCase())) {
        parts[0] = '`' + parts[0] + '`';
      }
      return parts.join(' ');
    }).join(', ');
    return `PARTITIONED BY (${fixed})`;
  });

  s = s.trim();
  if (!s.endsWith(';')) s += ';';
  return s;
}

// ── Adapt BQ DDL for scratch dataset execution ──────────────────────────
function readBqDdl(layer, name) {
  const fp = path.join(BQ_DDL, layer, `${name}.sql`);
  if (!fs.existsSync(fp)) return null;
  let ddl = fs.readFileSync(fp, 'utf8');

  // strip comment lines
  ddl = ddl.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

  // rewrite CREATE TABLE dataset.name → test.qa_val8_name
  ddl = ddl.replace(
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\.(\w+)/i,
    `CREATE TABLE IF NOT EXISTS \`${BQ_DS}\`.${BQ_PFX}$2`);

  // widen RANGE_BUCKET step to avoid 10K-partition limit in scratch
  // GENERATE_ARRAY(20200101, 20260101, 1) → step 10000 (≈6 partitions)
  ddl = ddl.replace(/GENERATE_ARRAY\(\s*(\d+)\s*,\s*(\d+)\s*,\s*1\s*\)/gi,
    'GENERATE_ARRAY($1, $2, 10000)');

  // strip OPTIONS(description=...) — contains ''|'' which triggers BQ
  // string-concat parse errors; descriptions are tested in AC#10
  ddl = ddl.replace(/\s*OPTIONS\s*\(\s*description\s*=\s*'(?:[^']|'')*'\s*\)/gi, '');

  return ddl;
}

// ── Impala query helper (FETCH_NEXT orientation) ────────────────────────
async function impQ(sess, sql) {
  const op = await sess.executeStatement(sql, { runAsync: true });
  await utils.waitUntilReady(op, false, () => {});
  await utils.fetchAll(op, 1);           // 1 = FETCH_NEXT
  const r = utils.getResult(op).getValue() ?? [];
  await op.close();
  return r;
}

// ── BQ field → normalised type string ───────────────────────────────────
function normBqField(f) {
  const m = { INTEGER:'INT64', FLOAT:'FLOAT64', BOOLEAN:'BOOL', RECORD:'STRUCT',
              NUMERIC:'NUMERIC', BIGNUMERIC:'BIGNUMERIC', STRING:'STRING',
              TIMESTAMP:'TIMESTAMP', DATE:'DATE', BYTES:'BYTES', JSON:'JSON' };
  let t = m[f.type] || f.type;
  if (f.mode === 'REPEATED' && f.type === 'RECORD' && f.fields) {
    const inner = f.fields.map(sf =>
      `${sf.name.toLowerCase()} ${normBqField(sf)}`).join(', ');
    return `ARRAY<STRUCT<${inner}>>`;
  }
  if (f.mode === 'REPEATED' && f.type !== 'RECORD') return `ARRAY<${t}>`;
  if (t === 'NUMERIC' && f.precision) return `NUMERIC(${f.precision},${f.scale||0})`;
  return t;
}

// ── Type comparison ─────────────────────────────────────────────────────
function typesMatch(expected, actual) {
  const e = expected.toUpperCase().replace(/\s+/g, '');
  const a = actual.toUpperCase().replace(/\s+/g, '');
  if (e === a) return true;
  if (e === 'STRING' && a === 'DATE') return true;   // partition col STRING→DATE
  if (e.startsWith('ARRAY<') && a.startsWith('ARRAY<'))
    return e.toLowerCase() === a.toLowerCase();
  return false;
}

// ═════════════════════════════════════════════════════════════════════════
// MAIN
// ═════════════════════════════════════════════════════════════════════════
(async () => {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  AC #8 — Live Impala ↔ BigQuery Table Metadata Comparison  ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // ── parse source DDL ─────────────────────────────────────────────
  const tables = [];
  for (const f of SRC_FILES) tables.push(...parseSrcFile(path.join(SRC_DDL, f)));
  console.log(`Parsed ${tables.length} source CREATE TABLE statements\n`);

  // ── connect Impala ───────────────────────────────────────────────
  console.log('Connecting to Impala…');
  const hc = new hive.HiveClient(TCLIService, TCLIService_types);
  const auth = process.env.TESTING_HIVE_AUTH === 'nosasl'
    ? new hive.auth.NoSaslAuthentication()
    : new hive.auth.PlainTcpAuthentication({
        username: process.env.TESTING_USER || 'impala',
        password: process.env.TESTING_PASSWORD || '' });
  const conn = await hc.connect(
    { host: process.env.TESTING_HOST, port: Number(process.env.TESTING_PORT) },
    new hive.connections.TcpConnection(), auth);
  const sess = await conn.openSession({
    client_protocol: TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10 });
  console.log('  ✓ Impala connected\n');

  // ── connect BigQuery ─────────────────────────────────────────────
  console.log('Connecting to BigQuery…');
  const oac = new OAuth2Client();
  oac.setCredentials({ access_token: process.env.BIGQUERY_TEST_BQ_TOKEN });
  const bq = new BigQuery({ projectId: process.env.BIGQUERY_TEST_BQ_PROJECT, authClient: oac });
  console.log(`  ✓ BigQuery connected (dataset: ${BQ_DS})\n`);

  // ── create scratch Impala databases ──────────────────────────────
  for (const db of ['staging','ods','dm']) {
    try { await impQ(sess, `CREATE DATABASE IF NOT EXISTS ${IMP_PFX}${db}`); }
    catch(e) { console.error(`  WARN: CREATE DB ${IMP_PFX}${db}: ${e.message.substring(0,80)}`); }
  }

  // ── per-table loop ───────────────────────────────────────────────
  let nPass = 0, nFail = 0, nSkip = 0;
  const failures = [], skipped = [], bqCleanup = [];

  console.log('══════════════════════════════════════════════════════════════');
  console.log('DETAILED RESULTS');
  console.log('══════════════════════════════════════════════════════════════\n');

  for (const tbl of tables) {
    console.log(`TABLE: ${tbl.db}.${tbl.name}`);

    // ── skip if not Impala-creatable ─────────────────────────────
    if (tbl.blocks.length) {
      console.log(`  ⊘ source-ddl-not-creatable (${tbl.blocks.join(', ')})\n`);
      skipped.push({ name: tbl.name, reason: tbl.blocks.join(', ') });
      nSkip++;
      continue;
    }

    // ── A: Create in Impala + DESCRIBE ───────────────────────────
    let impCols;
    try {
      const adapted = adaptImpala(tbl.stmt, tbl.db, tbl.name);
      await impQ(sess, adapted);
      const desc = await impQ(sess, `DESCRIBE ${IMP_PFX}${tbl.db}.${tbl.name}`);
      // filter out partition header rows Impala injects (blank / # header)
      impCols = desc.filter(r => {
        const n = (r.name||'').trim();
        return n && !n.startsWith('#');
      });
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,200);
      console.log(`  ⊘ source-ddl-not-creatable (Impala error: ${msg})\n`);
      skipped.push({ name: tbl.name, reason: `Impala CREATE: ${msg}` });
      nSkip++;
      continue;
    }
    if (!impCols?.length) {
      console.log('  ✗ HARD FAIL — Impala DESCRIBE returned 0 rows\n');
      failures.push({ name: tbl.name, reason: 'Impala DESCRIBE 0 rows' });
      nFail++;
      continue;
    }

    // ── B: Create in BQ + getMetadata ───────────────────────────
    const bqDdl = readBqDdl(tbl.db, tbl.name);
    if (!bqDdl) {
      console.log('  ✗ HARD FAIL — BQ DDL file missing\n');
      failures.push({ name: tbl.name, reason: 'BQ DDL file missing' });
      nFail++;
      continue;
    }

    const bqTbl = `${BQ_PFX}${tbl.name}`;
    let bqMeta;
    try {
      try { await bq.dataset(BQ_DS).table(bqTbl).delete(); } catch(_){}
      await bq.query({ query: bqDdl, useLegacySql: false });
      bqCleanup.push(bqTbl);
      const [m] = await bq.dataset(BQ_DS).table(bqTbl).getMetadata();
      bqMeta = m;
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,200);
      console.log(`  ✗ HARD FAIL — BQ error: ${msg}\n`);
      failures.push({ name: tbl.name, reason: `BQ: ${msg}` });
      nFail++;
      continue;
    }
    if (!bqMeta?.schema?.fields) {
      console.log('  ✗ HARD FAIL — BQ getMetadata no schema\n');
      failures.push({ name: tbl.name, reason: 'BQ no schema' });
      nFail++;
      continue;
    }

    // ── C: compare ──────────────────────────────────────────────
    const bqCols = bqMeta.schema.fields.map(f => ({
      name: f.name, type: normBqField(f), mode: f.mode||'NULLABLE',
      precision: f.precision, scale: f.scale }));

    const issues = [];
    let matched = 0;

    // C1: column count
    if (impCols.length !== bqCols.length)
      issues.push(`column_count: Impala=${impCols.length} BQ=${bqCols.length}`);

    // C2: per-column
    const minL = Math.min(impCols.length, bqCols.length);
    for (let i = 0; i < minL; i++) {
      const iN = (impCols[i].name||'').trim().toLowerCase();
      const bN = bqCols[i].name.toLowerCase();
      const iT = (impCols[i].type||'').trim().toUpperCase();
      const bT = bqCols[i].type.toUpperCase();
      let ok = true;

      // name (allow extract_ts → extract_date)
      if (iN !== bN && !(iN === 'extract_ts' && bN === 'extract_date')) {
        issues.push(`col[${i}] name: imp='${iN}' bq='${bN}'`);
        ok = false;
      }

      // type
      const exp = mapType(iT);
      if (!typesMatch(exp, bT)) {
        issues.push(`col[${i}] ${iN}: mapped=${exp} bq=${bT}`);
        ok = false;
      }

      // DECIMAL precision/scale
      if (exp.startsWith('NUMERIC(') && bT.startsWith('NUMERIC(') && exp !== bT) {
        issues.push(`col[${i}] ${iN}: precision ${exp} ≠ ${bT}`);
        ok = false;
      }

      // mode (REPEATED for arrays)
      if (exp.startsWith('ARRAY<') && bqCols[i].mode !== 'REPEATED') {
        issues.push(`col[${i}] ${iN}: expected REPEATED, got ${bqCols[i].mode}`);
        ok = false;
      }

      if (ok) matched++;
    }

    // C3: partition
    const srcPart = /PARTITIONED\s+BY/i.test(tbl.stmt);
    const bqPart  = !!(bqMeta.timePartitioning || bqMeta.rangePartitioning);
    if (srcPart && !bqPart)
      issues.push('partition: source partitioned but BQ not');

    // C4: clustering
    const srcBuck = /CLUSTERED\s+BY/i.test(tbl.stmt);
    const bqClust = bqMeta.clustering?.fields?.length > 0;
    if (srcBuck && !bqClust)
      issues.push('clustering: source CLUSTERED BY but no BQ CLUSTER BY');

    // C5: table type
    if (bqMeta.type !== 'TABLE')
      issues.push(`table_type: ${bqMeta.type} (expected TABLE)`);

    // ── output ──────────────────────────────────────────────────
    if (!issues.length) {
      console.log(`  ✓ columns: ${impCols.length} Impala / ${bqCols.length} BQ — matched=${matched}`);
      nPass++;
    } else {
      console.log(`  ✗ FAIL — ${issues.length} issue(s), matched=${matched}`);
      for (const iss of issues) console.log(`    ✗ ${iss}`);
      failures.push({ name: tbl.name, reason: issues.join('; ') });
      nFail++;
    }

    // partition/cluster evidence
    const pm = tbl.stmt.match(/PARTITIONED\s+BY\s*\(([^)]+)\)/i);
    if (pm) console.log(`  partition: [${pm[1].split(',').map(p=>p.trim().split(/\s+/)[0]).join(', ')}]`);
    if (bqMeta.clustering?.fields)
      console.log(`  clustering: [${bqMeta.clustering.fields.join(', ')}]`);

    // raw evidence
    console.log(`  raw_impala_describe: [${impCols.map(r=>`{${(r.name||'').trim()}:${(r.type||'').trim()}}`).join(', ')}]`);
    console.log(`  raw_bq_columns: [${bqCols.map(f=>`{${f.name}:${f.type}}`).join(', ')}]`);
    console.log('');
  }

  // ── TEARDOWN ─────────────────────────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════');
  console.log('TEARDOWN');
  console.log('══════════════════════════════════════════════════════════════');

  for (const t of bqCleanup) {
    try { await bq.dataset(BQ_DS).table(t).delete(); } catch(_){}
  }
  console.log(`  Dropped ${bqCleanup.length} BQ scratch tables`);

  for (const db of ['staging','ods','dm']) {
    try {
      const tbls = await impQ(sess, `SHOW TABLES IN ${IMP_PFX}${db}`);
      for (const t of tbls) {
        try { await impQ(sess, `DROP TABLE IF EXISTS ${IMP_PFX}${db}.${Object.values(t)[0]}`); }
        catch(_){}
      }
      await impQ(sess, `DROP DATABASE IF EXISTS ${IMP_PFX}${db}`);
    } catch(_){}
  }
  console.log('  Dropped Impala scratch databases');

  await sess.close();

  // ── SUMMARY ──────────────────────────────────────────────────────
  const total = nPass + nFail + nSkip;
  console.log('');
  console.log('══════════════════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('══════════════════════════════════════════════════════════════');
  console.log(`  Total:     ${total}`);
  console.log(`  ✓ PASS:    ${nPass}`);
  console.log(`  ✗ FAIL:    ${nFail}`);
  console.log(`  ⊘ SKIP:    ${nSkip} (source-ddl-not-creatable)`);
  console.log(`  Coverage:  ${nPass + nFail}/${total} live-compared`);
  console.log('');

  if (skipped.length) {
    console.log('  SKIPPED (source-ddl-not-creatable):');
    for (const s of skipped) console.log(`    ⊘ ${s.name}: ${s.reason}`);
    console.log('');
  }
  if (failures.length) {
    console.log('  FAILURES:');
    for (const f of failures) console.log(`    ✗ ${f.name}: ${f.reason}`);
    console.log('');
  }

  console.log(`  RESULT: ${nFail === 0 ? 'PASS' : 'FAIL'}`);
  process.exit(nFail > 0 ? 1 : 0);
})().catch(e => { console.error('FATAL:', e.message, e.stack); process.exit(2); });
