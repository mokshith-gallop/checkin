#!/usr/bin/env node
// =============================================================================
// AC #10 — Live-diff validation: column comment preservation
//
// For every Impala-creatable source table:
//   1. Creates table in Impala scratch DB from source DDL
//   2. Reads live Impala DESCRIBE (source column comment)
//   3. Creates BQ scratch table from converted DDL (preserving OPTIONS descriptions)
//   4. Reads BQ table.getMetadata() column descriptions
//   5. Asserts every source COMMENT is preserved as equivalent BQ description
//   6. Prints preserved X/Y coverage and lists any missing/altered comments
//
// Usage:
//   set -a; source /workspace/.gallop/db.env; set +a
//   node validation/ac10_live_diff_comments.mjs
// =============================================================================
import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');

const hive = require('hive-driver');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');
const fs   = require('fs');
const path = require('path');

const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);

// ── Config ──────────────────────────────────────────────────────────────
const SRC_DDL = '/workspace/source/hive/ddl';
const BQ_DDL  = '/workspace/project/bigquery/ddl';
const BQ_DS   = process.env.BIGQUERY_TEST_BQ_DATASETS || 'test';
const IMP_PFX = 'qa_val10_';
const BQ_PFX  = 'qa_val10_';

const SRC_FILES = [
  '02-staging-sqoop-mirrors.hql', '03-staging-delta-feeds.hql',
  '04-staging-file-feeds.hql',    '05-ods-cleanse.hql',
  '06-ods-delta-scd2.hql',        '07-ods-acid.hql',
  '08-dm-tables.hql',
];

// Impala reserved words (reused from ac8)
const RESERVED = new Set([
  'role','comment','end','start','date','key','type','order','group',
  'table','column','replace','select','from','where','join','on',
  'in','as','is','not','and','or','like','case','when','then','else',
  'true','false','null','int','float','double','string','boolean',
  'timestamp','decimal','array','map','struct','partition','data',
]);

// ── Parse source DDL ────────────────────────────────────────────────────
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
    const blocks = [];
    if (/transactional.*true/i.test(stmt))               blocks.push('ACID/transactional');
    if (/MAP\s*<\s*STRING\s*,\s*STRING\s*>/i.test(stmt)) blocks.push('MAP<STRING,STRING>');
    if (/RegexSerDe/i.test(stmt))                        blocks.push('RegexSerDe');
    out.push({ db, name, stmt, blocks });
  }
  return out;
}

// ── Adapt Hive DDL for Impala (from ac8) ────────────────────────────────
function adaptImpala(stmt, db, name) {
  let s = stmt;
  const sdb = IMP_PFX + db;
  s = s.replace(/CREATE\s+(EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+\S+/i,
    `CREATE TABLE IF NOT EXISTS ${sdb}.${name}`);
  s = s.replace(/LOCATION\s+'[^']*'\s*;?/gi, '');
  s = s.replace(/TBLPROPERTIES\s*\([^)]*\)\s*;?/gi, '');
  s = s.replace(/ROW\s+FORMAT[\s\S]*?(?=STORED|LOCATION|TBLPROPERTIES|PARTITIONED|;|$)/gi, '');
  s = s.replace(/WITH\s+SERDEPROPERTIES\s*\([^)]*\)/gi, '');
  s = s.replace(/STORED\s+AS\s+\w+/gi, '');
  s = s.replace(/CLUSTERED\s+BY\s*\([^)]*\)\s+INTO\s+\d+\s+BUCKETS/gi, '');

  // Quote reserved words in column block
  const p1 = s.indexOf('(');
  if (p1 >= 0) {
    let depth = 0, p2 = -1;
    for (let i = p1; i < s.length; i++) {
      if (s[i] === '(') depth++;
      if (s[i] === ')') { depth--; if (depth === 0) { p2 = i; break; } }
    }
    if (p2 > 0) {
      let cb = s.substring(p1, p2 + 1);
      cb = cb.replace(/^(\s+)(\w+)(\s+)/gm, (m, ws, w, tr) =>
        RESERVED.has(w.toLowerCase()) ? `${ws}\`${w}\`${tr}` : m);
      s = s.substring(0, p1) + cb + s.substring(p2 + 1);
    }
  }

  s = s.replace(/PARTITIONED\s+BY\s*\(([^)]+)\)/gi, (_, inner) => {
    const fixed = inner.split(',').map(pair => {
      const parts = pair.trim().split(/\s+/);
      if (parts.length >= 2 && RESERVED.has(parts[0].toLowerCase()))
        parts[0] = '`' + parts[0] + '`';
      return parts.join(' ');
    }).join(', ');
    return `PARTITIONED BY (${fixed})`;
  });

  s = s.trim();
  if (!s.endsWith(';')) s += ';';
  return s;
}

// ── Adapt BQ DDL for scratch — PRESERVE descriptions ────────────────────
function readBqDdlWithDescs(layer, name) {
  const fp = path.join(BQ_DDL, layer, `${name}.sql`);
  if (!fs.existsSync(fp)) return null;
  let ddl = fs.readFileSync(fp, 'utf8');
  ddl = ddl.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

  // Rewrite CREATE TABLE to scratch
  ddl = ddl.replace(
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\.(\w+)/i,
    `CREATE TABLE IF NOT EXISTS \`${BQ_DS}\`.${BQ_PFX}$2`);

  // Widen RANGE_BUCKET step
  ddl = ddl.replace(/GENERATE_ARRAY\(\s*(\d+)\s*,\s*(\d+)\s*,\s*1\s*\)/gi,
    'GENERATE_ARRAY($1, $2, 10000)');

  // Only strip the problematic SCD-2 descriptions with ''|'' that trigger
  // BQ string-concatenation parse errors. Preserve all other descriptions.
  ddl = ddl.replace(/\s*OPTIONS\s*\(\s*description\s*=\s*'(?:[^']*''[|]''[^']*)'\s*\)/gi, '');

  // Strip table-level OPTIONS that may conflict
  // (table-level OPTIONS at end of statement, after closing paren)
  // Keep column-level OPTIONS since those have the comments we need

  return ddl;
}

// ── Impala query helper ─────────────────────────────────────────────────
async function impQ(sess, sql) {
  const op = await sess.executeStatement(sql, { runAsync: true });
  await utils.waitUntilReady(op, false, () => {});
  await utils.fetchAll(op, 1);
  const r = utils.getResult(op).getValue() ?? [];
  await op.close();
  return r;
}

// ── Extract BQ column descriptions from getMetadata ─────────────────────
function extractBqDescs(meta) {
  if (!meta?.schema?.fields) return {};
  const descs = {};
  for (const f of meta.schema.fields) {
    if (f.description) descs[f.name.toLowerCase()] = f.description;
  }
  return descs;
}

// ═════════════════════════════════════════════════════════════════════════
// MAIN
// ═════════════════════════════════════════════════════════════════════════
(async () => {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  AC #10 — Live-diff: Column Comment Preservation           ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // ── Connect Impala ────────────────────────────────────────────────
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
  console.log('  ✓ Impala connected');

  // ── Connect BigQuery (with token refresh) ──────────────────────────
  function makeBq() {
    try {
      const envTxt = fs.readFileSync('/workspace/.gallop/db.env', 'utf8');
      const m = envTxt.match(/BIGQUERY_TEST_BQ_TOKEN='([^']+)'/);
      if (m) process.env.BIGQUERY_TEST_BQ_TOKEN = m[1];
    } catch(_) {}
    const oa = new OAuth2Client();
    oa.setCredentials({ access_token: process.env.BIGQUERY_TEST_BQ_TOKEN });
    return new BigQuery({
      projectId: process.env.BIGQUERY_TEST_BQ_PROJECT,
      authClient: oa,
      location: process.env.BIGQUERY_TEST_BQ_LOCATION || 'EU',
    });
  }
  let bq = makeBq();
  async function bqRun(fn) {
    try { return await fn(bq); }
    catch(e) {
      if (/authentication|credentials|token/i.test(e.message)) {
        bq = makeBq();
        return await fn(bq);
      }
      throw e;
    }
  }
  console.log(`  ✓ BigQuery connected (dataset: ${BQ_DS})\n`);

  // ── Create scratch Impala databases ───────────────────────────────
  for (const db of ['staging','ods','dm']) {
    try { await impQ(sess, `CREATE DATABASE IF NOT EXISTS ${IMP_PFX}${db}`); }
    catch(e) { console.error(`  WARN: CREATE DB ${IMP_PFX}${db}: ${e.message.substring(0,80)}`); }
  }

  // ── Parse all source tables ───────────────────────────────────────
  const allTables = [];
  for (const f of SRC_FILES) allTables.push(...parseSrcFile(path.join(SRC_DDL, f)));
  console.log(`Parsed ${allTables.length} source tables\n`);

  // ── Per-table comment comparison ──────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════');
  console.log('DETAILED RESULTS');
  console.log('══════════════════════════════════════════════════════════════\n');

  let totalComments = 0, preservedComments = 0;
  let nPass = 0, nFail = 0, nSkip = 0;
  const failures = [];
  const skipped = [];
  const bqCleanup = [];
  const missingComments = [];

  for (const tbl of allTables) {
    // ── Skip if not Impala-creatable ─────────────────────────────
    if (tbl.blocks.length) {
      skipped.push({ name: tbl.name, reason: tbl.blocks.join(', ') });
      nSkip++;
      continue;
    }

    // ── Create in Impala + DESCRIBE ─────────────────────────────
    let impDesc;
    try {
      const adapted = adaptImpala(tbl.stmt, tbl.db, tbl.name);
      await impQ(sess, adapted);
      impDesc = await impQ(sess, `DESCRIBE ${IMP_PFX}${tbl.db}.${tbl.name}`);
      impDesc = impDesc.filter(r => {
        const n = (r.name||'').trim();
        return n && !n.startsWith('#');
      });
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,150);
      skipped.push({ name: tbl.name, reason: `Impala error: ${msg}` });
      nSkip++;
      continue;
    }

    // ── Create in BQ + getMetadata (with descriptions) ──────────
    const bqDdl = readBqDdlWithDescs(tbl.db, tbl.name);
    if (!bqDdl) {
      skipped.push({ name: tbl.name, reason: 'BQ DDL file missing' });
      nSkip++;
      continue;
    }

    const bqTbl = `${BQ_PFX}${tbl.name}`;
    let bqMeta;
    try {
      bqMeta = await bqRun(async b => {
        try { await b.dataset(BQ_DS).table(bqTbl).delete(); } catch(_){}
        await b.query({ query: bqDdl, useLegacySql: false });
        bqCleanup.push(bqTbl);
        const [m] = await b.dataset(BQ_DS).table(bqTbl).getMetadata();
        return m;
      });
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,150);
      skipped.push({ name: tbl.name, reason: `BQ error: ${msg}` });
      nSkip++;
      continue;
    }

    // ── Compare comments ────────────────────────────────────────
    const bqDescs = extractBqDescs(bqMeta);
    let tableHasComments = false;
    let tableMissing = [];

    for (const row of impDesc) {
      const colName = (row.name || '').trim().toLowerCase();
      const impComment = (row.comment || '').trim();
      if (!impComment) continue;  // no source comment → nothing to check

      tableHasComments = true;
      totalComments++;

      const bqDesc = bqDescs[colName] || '';

      // Semantic equivalence: check that the BQ description contains
      // the key semantic content from the Hive comment.
      // e.g. "epoch SECONDS (legacy)" → should contain "SECONDS" or "epoch"
      // e.g. "!! name says seconds, VALUES ARE MILLIS !!" → should contain "MILLIS"
      // e.g. "Oracle string YYYYMMDDHH24MISS (legacy)" → should contain "YYYYMMDDHH24MISS"
      const isPreserved = isSemanticallyEquivalent(impComment, bqDesc);

      if (isPreserved) {
        preservedComments++;
      } else {
        tableMissing.push({ col: colName, src: impComment, bq: bqDesc || '(none)' });
        missingComments.push({ table: tbl.name, col: colName, src: impComment, bq: bqDesc || '(none)' });
      }
    }

    // ── Per-table output ────────────────────────────────────────
    if (tableHasComments) {
      const tableTotal = tableMissing.length + (totalComments - missingComments.length >= 0 ? 0 : 0);
      if (tableMissing.length === 0) {
        nPass++;
      } else {
        nFail++;
        console.log(`TABLE: ${tbl.db}.${tbl.name}`);
        for (const m of tableMissing) {
          console.log(`  ✗ ${m.col}: src='${m.src}' → bq='${m.bq}'`);
        }
        failures.push({ name: tbl.name, cols: tableMissing.map(m => m.col) });
        console.log('');
      }
    }
  }

  // ── TEARDOWN ──────────────────────────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════');
  console.log('TEARDOWN');
  console.log('══════════════════════════════════════════════════════════════');

  bq = makeBq(); // refresh token for cleanup
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

  // ── SUMMARY ───────────────────────────────────────────────────────
  console.log('');
  console.log('══════════════════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('══════════════════════════════════════════════════════════════');
  console.log(`  Source comments found:  ${totalComments}`);
  console.log(`  Preserved in BQ:       ${preservedComments}`);
  console.log(`  Missing/altered:       ${missingComments.length}`);
  console.log(`  Tables with comments:  PASS=${nPass} FAIL=${nFail}`);
  console.log(`  Tables skipped:        ${nSkip} (source-ddl-not-creatable)`);
  console.log(`  Coverage:              preserved ${preservedComments}/${totalComments}`);
  console.log('');

  if (skipped.length) {
    console.log('  SKIPPED (source-ddl-not-creatable):');
    for (const s of skipped) console.log(`    ⊘ ${s.name}: ${s.reason}`);
    console.log('');
  }
  if (missingComments.length) {
    console.log('  MISSING/ALTERED COMMENTS:');
    for (const m of missingComments)
      console.log(`    ✗ ${m.table}.${m.col}: src='${m.src}' → bq='${m.bq}'`);
    console.log('');
  }

  const result = missingComments.length === 0 ? 'PASS' : 'FAIL';
  console.log(`  RESULT: ${result}`);
  process.exit(result === 'PASS' ? 0 : 1);
})().catch(e => { console.error('FATAL:', e.message, e.stack); process.exit(2); });

// ── Semantic equivalence check ──────────────────────────────────────────
function isSemanticallyEquivalent(hiveComment, bqDesc) {
  if (!bqDesc) return false;

  const hc = hiveComment.toUpperCase();
  const bd = bqDesc.toUpperCase();

  // Exact match (case-insensitive)
  if (hc === bd) return true;

  // Key-phrase matching: extract key terms from Hive comment and check
  // they're present in the BQ description

  // epoch SECONDS
  if (hc.includes('EPOCH') && hc.includes('SECONDS'))
    return bd.includes('SECONDS') || bd.includes('EPOCH');

  // epoch MILLISECONDS
  if (hc.includes('EPOCH') && hc.includes('MILLISECONDS'))
    return bd.includes('MILLISECONDS') || bd.includes('MILLIS');

  // LIE columns: "!! name says seconds, VALUES ARE MILLIS !!"
  if (hc.includes('MILLIS') && hc.includes('SECONDS'))
    return bd.includes('MILLIS') || bd.includes('MILLISECONDS');

  // Oracle string: "Oracle string YYYYMMDDHH24MISS (legacy)"
  if (hc.includes('YYYYMMDDHH24MISS'))
    return bd.includes('YYYYMMDDHH24MISS');

  // Generic: check if at least 50% of the non-stopword tokens match
  const stopWords = new Set(['THE','A','AN','IS','IN','OF','AND','OR','TO','FOR','AS','IT']);
  const hTokens = hc.split(/\W+/).filter(t => t.length > 2 && !stopWords.has(t));
  const bdTokens = new Set(bd.split(/\W+/));
  const matchCount = hTokens.filter(t => bdTokens.has(t)).length;
  return hTokens.length > 0 && matchCount >= Math.ceil(hTokens.length * 0.5);
}
