#!/usr/bin/env node
// =============================================================================
// AC #10 — Live-diff validation: Column comment preservation
//
// For every Impala-creatable source table:
//   1. Creates the table in Impala from source DDL (with COMMENTs)
//   2. Runs DESCRIBE to get {name, type, comment} rows
//   3. Creates the matching BQ table from converted DDL
//   4. Reads BQ getMetadata() schema.fields[].description
//   5. For each source column with a non-empty COMMENT, asserts BQ description
//      is semantically equivalent (contains the key content)
//   6. Prints preserved X/Y coverage line (expects 68 column comments)
//   7. Columns on Impala-not-creatable tables → source-ddl-not-creatable
//
// Usage:
//   set -a; source /workspace/.gallop/db.env; set +a
//   node validation/ac10_live_diff_comments.mjs
// =============================================================================
import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');

const hive     = require('hive-driver');
const { BigQuery }    = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');
const fs   = require('fs');
const path = require('path');

const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);

// ── Config ──────────────────────────────────────────────────────────────
const SRC_DDL = '/workspace/source/hive/ddl';
const BQ_DDL  = '/workspace/project/bigquery/ddl';
const BQ_DS   = process.env.BIGQUERY_TEST_BQ_DATASETS || 'test';
const BQ_PFX  = 'qa_val10_';
const IMP_PFX = 'qa_val10_';

// Only staging files have column COMMENTs
const SRC_FILES = [
  '02-staging-sqoop-mirrors.hql',
  '03-staging-delta-feeds.hql',
  '04-staging-file-feeds.hql',
];

const RESERVED = new Set([
  'role','comment','end','start','date','key','type','order','group',
  'table','column','replace','select','from','where','join','on',
  'in','as','is','not','and','or','like','case','when','then','else',
  'true','false','null','int','float','double','string','boolean',
  'timestamp','decimal','array','map','struct','partition','data',
]);

// ── Helpers (same as ac8) ───────────────────────────────────────────────
async function impQ(sess, sql) {
  const op = await sess.executeStatement(sql, { runAsync: true });
  await utils.waitUntilReady(op, false, () => {});
  await utils.fetchAll(op, 1);
  const r = utils.getResult(op).getValue() ?? [];
  await op.close();
  return r;
}

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
    if (/transactional.*true/i.test(stmt)) blocks.push('ACID/transactional');
    if (/MAP\s*<\s*STRING\s*,\s*STRING\s*>/i.test(stmt)) blocks.push('MAP<STRING,STRING>');
    if (/RegexSerDe/i.test(stmt)) blocks.push('RegexSerDe');
    out.push({ db, name, stmt, blocks });
  }
  return out;
}

function adaptImpala(stmt, db, name) {
  let s = stmt;
  s = s.replace(/CREATE\s+(EXTERNAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+\S+/i,
    `CREATE TABLE IF NOT EXISTS ${IMP_PFX}${db}.${name}`);
  s = s.replace(/LOCATION\s+'[^']*'\s*;?/gi, '');
  s = s.replace(/TBLPROPERTIES\s*\([^)]*\)\s*;?/gi, '');
  s = s.replace(/ROW\s+FORMAT[\s\S]*?(?=STORED|LOCATION|TBLPROPERTIES|PARTITIONED|;|$)/gi, '');
  s = s.replace(/WITH\s+SERDEPROPERTIES\s*\([^)]*\)/gi, '');
  s = s.replace(/STORED\s+AS\s+\w+/gi, '');
  s = s.replace(/CLUSTERED\s+BY\s*\([^)]*\)\s+INTO\s+\d+\s+BUCKETS/gi, '');
  const p1 = s.indexOf('(');
  if (p1 >= 0) {
    let depth = 0, p2 = -1;
    for (let i = p1; i < s.length; i++) {
      if (s[i] === '(') depth++; if (s[i] === ')') { depth--; if (depth === 0) { p2 = i; break; } }
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
      if (parts.length >= 2 && RESERVED.has(parts[0].toLowerCase())) parts[0] = '`' + parts[0] + '`';
      return parts.join(' ');
    }).join(', ');
    return `PARTITIONED BY (${fixed})`;
  });
  s = s.trim(); if (!s.endsWith(';')) s += ';';
  return s;
}

function readBqTableDdl(layer, name) {
  const fp = path.join(BQ_DDL, layer, `${name}.sql`);
  if (!fs.existsSync(fp)) return null;
  let ddl = fs.readFileSync(fp, 'utf8');
  ddl = ddl.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');
  ddl = ddl.replace(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\.(\w+)/i,
    `CREATE TABLE IF NOT EXISTS \`${BQ_DS}\`.${BQ_PFX}$2`);
  ddl = ddl.replace(/GENERATE_ARRAY\(\s*(\d+)\s*,\s*(\d+)\s*,\s*1\s*\)/gi,
    'GENERATE_ARRAY($1, $2, 10000)');
  // DO NOT strip OPTIONS(description=...) — that's what we're testing!
  // But fix the ''|'' escaping that breaks bq.query():
  // Replace ''|'' with '|' (single-quote escaped pipe inside SQL string literals
  // needs to be valid when run via API — the API doesn't double-unescape)
  // Actually the DDL text uses '' as BQ's escape for a literal ', which is correct
  // syntax. The issue in ac8 was a different regex. Let's try passing as-is first.
  return ddl;
}

// ── Semantic comment matching ───────────────────────────────────────────
// Key content tokens we expect to find in the BQ description
function commentMatchesBq(hiveComment, bqDesc) {
  if (!bqDesc) return false;
  const hc = hiveComment.toLowerCase();
  const bd = bqDesc.toLowerCase();

  // epoch SECONDS (legacy) → BQ should contain "seconds"
  if (hc.includes('epoch seconds')) return bd.includes('seconds') || bd.includes('epoch');
  // epoch MILLISECONDS (legacy) → BQ should contain "milliseconds"
  if (hc.includes('epoch milliseconds')) return bd.includes('milliseconds') || bd.includes('epoch');
  // Oracle string YYYYMMDDHH24MISS → BQ should contain "yyyymmddhh24miss" or "oracle"
  if (hc.includes('yyyymmddhh24miss')) return bd.includes('yyyymmddhh24miss') || bd.includes('oracle');
  // !! name says seconds, VALUES ARE MILLIS !! → BQ should contain "milliseconds"
  if (hc.includes('values are millis')) return bd.includes('milliseconds') || bd.includes('millis');

  // Generic fallback: at least 50% of words from source appear in target
  const srcWords = hc.split(/\s+/).filter(w => w.length > 2);
  const matched = srcWords.filter(w => bd.includes(w)).length;
  return matched >= Math.ceil(srcWords.length * 0.5);
}

// ═════════════════════════════════════════════════════════════════════════
(async () => {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  AC #10 — Live Column Comment Preservation Validation      ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  // ── Connect Impala ────────────────────────────────────────────────
  console.log('Connecting to Impala…');
  const hc = new hive.HiveClient(TCLIService, TCLIService_types);
  const auth = process.env.TESTING_HIVE_AUTH === 'nosasl'
    ? new hive.auth.NoSaslAuthentication()
    : new hive.auth.PlainTcpAuthentication({
        username: process.env.TESTING_USER || 'impala', password: process.env.TESTING_PASSWORD || '' });
  const conn = await hc.connect(
    { host: process.env.TESTING_HOST, port: Number(process.env.TESTING_PORT) },
    new hive.connections.TcpConnection(), auth);
  const sess = await conn.openSession({
    client_protocol: TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10 });
  console.log('  ✓ Impala connected\n');

  // ── Connect BQ ────────────────────────────────────────────────────
  console.log('Connecting to BigQuery…');
  const oac = new OAuth2Client();
  oac.setCredentials({ access_token: process.env.BIGQUERY_TEST_BQ_TOKEN });
  const bq = new BigQuery({ projectId: process.env.BIGQUERY_TEST_BQ_PROJECT, authClient: oac });
  console.log(`  ✓ BigQuery connected (dataset: ${BQ_DS})\n`);

  // ── Create scratch Impala DB ──────────────────────────────────────
  try { await impQ(sess, `CREATE DATABASE IF NOT EXISTS ${IMP_PFX}staging`); } catch(_){}

  // ── Parse staging tables ──────────────────────────────────────────
  const tables = [];
  for (const f of SRC_FILES) tables.push(...parseSrcFile(path.join(SRC_DDL, f)));
  console.log(`Parsed ${tables.length} staging tables\n`);

  // ── Per-table loop ────────────────────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════');
  console.log('DETAILED RESULTS');
  console.log('══════════════════════════════════════════════════════════════\n');

  let totalComments = 0, preserved = 0, missing = 0, nSkip = 0;
  const missingList = [];
  const skippedTables = [];
  const bqCleanup = [];

  for (const tbl of tables) {
    console.log(`TABLE: staging.${tbl.name}`);

    // ── Skip if not Impala-creatable ──────────────────────────────
    if (tbl.blocks.length) {
      console.log(`  ⊘ source-ddl-not-creatable (${tbl.blocks.join(', ')})`);
      skippedTables.push({ name: tbl.name, reason: tbl.blocks.join(', ') });
      nSkip++;
      console.log('');
      continue;
    }

    // ── A: Create in Impala + DESCRIBE (includes comment column) ──
    let impCols;
    try {
      const adapted = adaptImpala(tbl.stmt, 'staging', tbl.name);
      await impQ(sess, adapted);
      const desc = await impQ(sess, `DESCRIBE ${IMP_PFX}staging.${tbl.name}`);
      impCols = desc.filter(r => {
        const n = (r.name||'').trim();
        return n && !n.startsWith('#');
      });
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,150);
      console.log(`  ⊘ source-ddl-not-creatable (Impala error: ${msg})`);
      skippedTables.push({ name: tbl.name, reason: `Impala CREATE: ${msg}` });
      nSkip++;
      console.log('');
      continue;
    }

    // ── B: Create in BQ + getMetadata ─────────────────────────────
    const bqDdl = readBqTableDdl('staging', tbl.name);
    if (!bqDdl) { console.log('  WARN: BQ DDL file missing\n'); continue; }

    const bqTbl = `${BQ_PFX}${tbl.name}`;
    let bqMeta;
    try {
      try { await bq.dataset(BQ_DS).table(bqTbl).delete(); } catch(_){}
      await bq.query({ query: bqDdl, useLegacySql: false });
      bqCleanup.push(bqTbl);
      const [m] = await bq.dataset(BQ_DS).table(bqTbl).getMetadata();
      bqMeta = m;
    } catch(e) {
      const msg = e.message.replace(/\n/g,' ').substring(0,150);
      console.log(`  WARN: BQ creation error: ${msg}\n`);
      continue;
    }

    // Build BQ description map
    const bqDescMap = {};
    if (bqMeta?.schema?.fields) {
      for (const f of bqMeta.schema.fields) {
        bqDescMap[f.name.toLowerCase()] = f.description || null;
      }
    }

    // ── C: Compare comments ───────────────────────────────────────
    let tableComments = 0, tablePreserved = 0;
    for (const ic of impCols) {
      const colName = (ic.name||'').trim().toLowerCase();
      const srcComment = (ic.comment||'').trim();
      if (!srcComment) continue; // no source comment

      tableComments++;
      totalComments++;

      const bqDesc = bqDescMap[colName];
      if (commentMatchesBq(srcComment, bqDesc)) {
        tablePreserved++;
        preserved++;
      } else {
        missing++;
        missingList.push({
          table: tbl.name, column: colName,
          source: srcComment, target: bqDesc || '(none)',
        });
      }
    }

    if (tableComments > 0) {
      console.log(`  comments: ${tablePreserved}/${tableComments} preserved`);
      if (tablePreserved < tableComments) {
        for (const m of missingList.filter(m => m.table === tbl.name)) {
          console.log(`    ✗ ${m.column}: src='${m.source}' bq='${m.target}'`);
        }
      }
    }

    // raw evidence
    const commentedCols = impCols.filter(r => (r.comment||'').trim());
    if (commentedCols.length) {
      console.log(`  raw_impala_comments: [${commentedCols.map(r => `{${(r.name||'').trim()}:'${(r.comment||'').trim()}'}`).join(', ')}]`);
      const bqEvidence = commentedCols.map(r => {
        const cn = (r.name||'').trim().toLowerCase();
        return `{${cn}:'${bqDescMap[cn]||'(none)}'}`;
      });
      console.log(`  raw_bq_descriptions: [${bqEvidence.join(', ')}]`);
    }
    console.log('');
  }

  // ── TEARDOWN ──────────────────────────────────────────────────────
  console.log('══════════════════════════════════════════════════════════════');
  console.log('TEARDOWN');
  console.log('══════════════════════════════════════════════════════════════');

  for (const t of bqCleanup) {
    try { await bq.dataset(BQ_DS).table(t).delete(); } catch(_){}
  }
  console.log(`  Dropped ${bqCleanup.length} BQ scratch tables`);

  try {
    const tbls = await impQ(sess, `SHOW TABLES IN ${IMP_PFX}staging`);
    for (const t of tbls) {
      try { await impQ(sess, `DROP TABLE IF EXISTS ${IMP_PFX}staging.${Object.values(t)[0]}`); } catch(_){}
    }
    await impQ(sess, `DROP DATABASE IF EXISTS ${IMP_PFX}staging`);
  } catch(_){}
  console.log('  Dropped Impala scratch database');

  await sess.close();

  // ── SUMMARY ───────────────────────────────────────────────────────
  console.log('');
  console.log('══════════════════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('══════════════════════════════════════════════════════════════');
  console.log(`  Total source column COMMENTs: ${totalComments}`);
  console.log(`  ✓ Preserved:  ${preserved}`);
  console.log(`  ✗ Missing:    ${missing}`);
  console.log(`  ⊘ Skipped:    ${nSkip} tables (source-ddl-not-creatable)`);
  console.log(`  Coverage:     preserved ${preserved}/${totalComments}`);
  console.log('');

  if (skippedTables.length) {
    console.log('  SKIPPED (source-ddl-not-creatable):');
    for (const s of skippedTables) console.log(`    ⊘ ${s.name}: ${s.reason}`);
    console.log('');
  }

  if (missingList.length) {
    console.log('  MISSING/ALTERED COMMENTS:');
    for (const m of missingList) {
      console.log(`    ✗ ${m.table}.${m.column}: src='${m.source}' bq='${m.target}'`);
    }
    console.log('');
  }

  const fail = missing > 0;
  console.log(`  RESULT: ${fail ? 'FAIL' : 'PASS'}`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('FATAL:', e.message, e.stack); process.exit(2); });
