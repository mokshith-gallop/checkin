#!/usr/bin/env node
// audit_ddl_v2.mjs — Comprehensive DDL audit: manifest vs BigQuery DDL files
// Parses manifests/tables.yaml and compares against every BigQuery DDL file.
// Checks: column count, column names, type mappings, partition handling,
//         COMMENT preservation, SCD-2 descriptions, format provenance.
// Usage: node scripts/audit_ddl_v2.mjs

import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

const MANIFEST = '/workspace/source/manifests/tables.yaml';
const HIVE_DDL = '/workspace/source/hive/ddl';
const BQ_DDL = '/workspace/project/bigquery/ddl';

// ── Simple YAML parser for our manifest format ────────────────────────────
function parseManifest(yaml) {
  const tables = [];
  const lines = yaml.split('\n');
  let current = null;
  let inColumns = false;

  for (const line of lines) {
    if (/^\s{2}- name:\s*(\S+)/.test(line)) {
      if (current) tables.push(current);
      current = { name: line.match(/name:\s*(\S+)/)[1], db: null, group: null, format: null, partition: [], bucketing: null, columns: [], isAcid: false };
      inColumns = false;
    }
    if (!current) continue;
    if (/^\s{4}db:\s*(\S+)/.test(line)) current.db = line.match(/db:\s*(\S+)/)[1];
    if (/^\s{4}group:\s*(\S+)/.test(line)) current.group = line.match(/group:\s*(\S+)/)[1];
    if (/^\s{4}format:\s*(\S+)/.test(line)) {
      current.format = line.match(/format:\s*(\S+)/)[1];
      if (current.format === 'ORC_ACID') current.isAcid = true;
    }
    if (/^\s{4}partition:\s*\[(.+)\]/.test(line)) {
      current.partition = line.match(/partition:\s*\[(.+)\]/)[1].split(',').map(p => {
        const [name, type] = p.trim().split(':');
        return { name: name.trim(), type: type.trim() };
      });
    }
    if (/^\s{4}bucketing:/.test(line)) {
      const m = line.match(/by:\s*(\w+)/);
      if (m) current.bucketing = { by: m[1] };
    }
    if (/^\s{4}columns:/.test(line)) { inColumns = true; continue; }
    if (inColumns) {
      if (/^\s{4}\w/.test(line) && !/^\s{6}/.test(line)) { inColumns = false; continue; }
      const sm = line.match(/^\s+- (\w+):([A-Z][A-Za-z0-9(,)]+)(?::([^#\s]+(?:,[^#\s]+)*))?(?:\s*#.*)?$/);
      if (sm) { current.columns.push({ name: sm[1], type: sm[2].trim(), tags: sm[3] || '' }); continue; }
      const cm = line.match(/^\s+- \{name:\s*(\w+),\s*type:\s*"?([^"{}]+?)"?\s*(?:,\s*tags:\s*\[([^\]]*)\])?\s*\}$/);
      if (cm) current.columns.push({ name: cm[1], type: cm[2].trim().replace(/,$/, '').trim(), tags: cm[3] || '' });
    }
  }
  if (current) tables.push(current);
  return tables;
}

// ── Parse BigQuery DDL file ───────────────────────────────────────────────
function parseBqFile(rawContent) {
  if (/CREATE\s+VIEW/i.test(rawContent)) return null;
  const content = rawContent.replace(/--.*$/gm, '');
  const nm = content.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\.(\w+)/i);
  if (!nm) return null;
  const si = content.indexOf('(', content.indexOf(nm[0]));
  let d = 0, ei = -1;
  for (let i = si; i < content.length; i++) {
    if (content[i] === '(') d++;
    if (content[i] === ')') { d--; if (d === 0) { ei = i; break; } }
  }
  if (ei < 0) return null;
  const cb = content.substring(si + 1, ei), rest = content.substring(ei + 1);
  // Split columns
  const split = (block) => {
    const r = []; let dd = 0, s = false, c = '';
    for (const ch of block) {
      if (ch === "'" ) { s = !s; c += ch; continue; }
      if (s) { c += ch; continue; }
      if (ch === '<' || ch === '(') dd++;
      if (ch === '>' || ch === ')') dd--;
      if (ch === ',' && dd === 0) { if (c.trim()) r.push(c.trim()); c = ''; }
      else c += ch;
    }
    if (c.trim()) r.push(c.trim());
    return r;
  };
  const cols = split(cb);
  // Parse raw for descriptions
  const rsi = rawContent.indexOf('(', rawContent.lastIndexOf('CREATE TABLE'));
  let rd = 0, rei = -1;
  for (let i = rsi; i < rawContent.length; i++) {
    if (rawContent[i] === '(') rd++;
    if (rawContent[i] === ')') { rd--; if (rd === 0) { rei = i; break; } }
  }
  const rawCols = split(rawContent.substring(rsi + 1, rei));
  const parsed = cols.map((c, i) => {
    const rc = rawCols[i] || c;
    const dm = rc.match(/OPTIONS\s*\(\s*description\s*=\s*'((?:[^'\\]|''|\\.)*)'\s*\)/i);
    const desc = dm ? dm[1].replace(/''/g, "'") : null;
    const wo = c.replace(/\s*OPTIONS\s*\(.*\)\s*$/i, '').trim();
    const p = wo.match(/^(\w+)\s+(.+)$/);
    return p ? { name: p[1], type: p[2].trim(), description: desc } : { name: '??', type: c, description: null };
  });
  const pm = rest.match(/PARTITION\s+BY\s+(.+?)(?:\n|;|$)/im);
  const cm = rest.match(/CLUSTER\s+BY\s+(.+?)(?:\n|;|$)/im);
  const tm = rawContent.match(/\n\s*OPTIONS\s*\(\s*description\s*=\s*'((?:[^'\\]|''|\\.)*)'\s*\)\s*;/i);
  return { ds: nm[1], name: nm[2], cols: parsed,
    partition: pm ? pm[1].trim().replace(/;$/, '') : null,
    cluster: cm ? cm[1].trim().replace(/;$/, '') : null,
    tableDesc: tm ? tm[1] : null };
}

// ── Type mapping ──────────────────────────────────────────────────────────
function hiveToExpectedBq(t) {
  t = t.toUpperCase().replace(/\s+/g, '');
  if (t === 'BIGINT' || t === 'INT' || t === 'SMALLINT') return 'INT64';
  if (t === 'STRING') return 'STRING';
  if (t === 'BOOLEAN') return 'BOOL';
  if (t === 'DOUBLE') return 'FLOAT64';
  if (t === 'TIMESTAMP') return 'TIMESTAMP';
  if (t === 'DATE') return 'DATE';
  if (t.match(/^DECIMAL\(\d+,\d+\)$/)) return t.replace('DECIMAL', 'NUMERIC');
  if (t === 'ARRAY<STRING>') return 'ARRAY<STRING>';
  if (t.startsWith('MAP<')) return 'JSON';
  if (t.startsWith('ARRAY<STRUCT<'))
    return t.replace(/\bBIGINT\b/g, 'INT64').replace(/(?<![A-Z])INT(?![A-Z0-9])/g, 'INT64')
            .replace(/\bBOOLEAN\b/g, 'BOOL').replace(/:/g, ' ').replace(/,/g, ', ');
  return t;
}

// ── Main ──────────────────────────────────────────────────────────────────
const manifestTables = parseManifest(readFileSync(MANIFEST, 'utf8'));
console.log(`Parsed ${manifestTables.length} tables from manifest\n`);

// Load Hive comments
const allHiveComments = {};
for (const f of readdirSync(HIVE_DDL).filter(f => f.endsWith('.hql'))) {
  const stmts = readFileSync(join(HIVE_DDL, f), 'utf8').split(/(?=CREATE\s)/i);
  for (const stmt of stmts) {
    const nm = stmt.match(/TABLE\s+IF\s+NOT\s+EXISTS\s+\w+\.(\w+)/i);
    if (!nm) continue;
    const comments = {};
    let m; const re = /^\s+(\w+)\s+\w[^\n]*?COMMENT\s+'([^']+)'/gm;
    while ((m = re.exec(stmt)) !== null) comments[m[1]] = m[2];
    allHiveComments[nm[1]] = comments;
  }
}

// Load BQ DDL files
const bqFiles = {};
for (const sd of ['staging', 'ods', 'dm']) {
  for (const f of readdirSync(join(BQ_DDL, sd)).filter(f => f.endsWith('.sql'))) {
    const p = parseBqFile(readFileSync(join(BQ_DDL, sd, f), 'utf8'));
    if (p) bqFiles[p.name] = { ...p, file: `${sd}/${f}` };
  }
}

const issues = []; let pass = 0, total = 0;

for (const tbl of manifestTables) {
  const key = `${tbl.db}.${tbl.name}`, bq = bqFiles[tbl.name];
  if (!bq) { issues.push({ table: key, type: 'MISSING', detail: 'No BQ DDL file' }); continue; }

  const exp = tbl.columns.length + tbl.partition.length;
  total++; if (bq.cols.length !== exp) issues.push({ table: key, type: 'COL_COUNT', detail: `Expected ${exp} (${tbl.columns.length}+${tbl.partition.length}), got ${bq.cols.length}` }); else pass++;

  for (let i = 0; i < tbl.columns.length && i < bq.cols.length; i++) {
    const mc = tbl.columns[i], bc = bq.cols[i];
    total++; if (mc.name !== bc.name) issues.push({ table: key, type: 'COL_NAME', detail: `[${i}] '${mc.name}' vs '${bc.name}'` }); else pass++;
    total++; const et = hiveToExpectedBq(mc.type), ne = et.replace(/\s+/g,'').toUpperCase(), nb = bc.type.replace(/\s+/g,'').toUpperCase();
    if (ne !== nb) issues.push({ table: key, type: 'COL_TYPE', detail: `'${mc.name}': ${et} vs ${bc.type}` }); else pass++;
  }

  for (const pc of tbl.partition) {
    total++; const pn = pc.name === 'extract_ts' ? 'extract_date' : pc.name;
    const found = bq.cols.find(c => c.name === pn);
    if (!found) { issues.push({ table: key, type: 'PART_MISSING', detail: `'${pn}' not inlined` }); continue; }
    pass++; total++;
    const dateCols = ['load_date','feed_date','snapshot_date','event_date','call_date','sched_date'];
    const monthCols = ['work_month','period_month','swap_month','event_month'];
    if (dateCols.includes(pn) || pc.name === 'extract_ts' || monthCols.includes(pn)) {
      if (found.type !== 'DATE') issues.push({ table: key, type: 'PART_TYPE', detail: `'${pn}' → DATE, got ${found.type}` }); else pass++;
    } else if (['INT','BIGINT'].includes(pc.type)) {
      if (found.type !== 'INT64') issues.push({ table: key, type: 'PART_TYPE', detail: `'${pn}' → INT64, got ${found.type}` }); else pass++;
    } else pass++;
  }

  // Multi-col partition demoting
  if (tbl.partition.length > 1) {
    total++;
    const demoted = tbl.name === 'stg_wfm_schedule' ? 'site_code' :
                    tbl.name === 'fact_interaction' ? 'channel' :
                    tbl.partition[0].name; // client_code for file feeds
    if (!bq.cluster || !bq.cluster.includes(demoted)) issues.push({ table: key, type: 'MULTI_PART', detail: `'${demoted}' not in CLUSTER BY` }); else pass++;
  }

  // Bucketing → CLUSTER BY
  if (tbl.bucketing) { total++; if (!bq.cluster || !bq.cluster.includes(tbl.bucketing.by)) issues.push({ table: key, type: 'BUCKET', detail: `${tbl.bucketing.by} not in CLUSTER BY` }); else pass++; }

  // ACID: no partition
  if (tbl.isAcid) { total++; if (bq.partition) issues.push({ table: key, type: 'ACID', detail: 'Should not have PARTITION' }); else pass++; }

  // Comment preservation
  const hc = allHiveComments[tbl.name] || {};
  for (const [cn, comment] of Object.entries(hc)) {
    total++; const bc = bq.cols.find(c => c.name === cn);
    if (!bc || !bc.description) { issues.push({ table: key, type: 'COMMENT', detail: `'${cn}' missing desc` }); continue; }
    const h = comment.toLowerCase(), b = bc.description.toLowerCase();
    let ok = false;
    if (h.includes('epoch seconds')) ok = b.includes('epoch seconds') || b.includes('seconds');
    else if (h.includes('epoch milliseconds')) ok = b.includes('milliseconds') || b.includes('millis');
    else if (h.includes('yyyymmddhh24miss')) ok = b.includes('yyyymmddhh24miss') || b.includes('oracle');
    else if (h.includes('values are millis')) ok = b.includes('millis') || b.includes('milliseconds');
    else ok = b.includes(h.substring(0, 15));
    if (ok) pass++; else issues.push({ table: key, type: 'COMMENT_MISMATCH', detail: `'${cn}': '${comment}' vs '${bc.description}'` });
  }

  // SCD-2 keys
  if (tbl.group === 'scd2') {
    total++; const sk = bq.cols.find(c => c.name === tbl.columns[0].name);
    if (!sk || !sk.description || !sk.description.includes('TO_HEX(MD5(')) issues.push({ table: key, type: 'SCD2', detail: `SK desc missing TO_HEX(MD5(...))` }); else pass++;
  }

  // Format descriptions
  if (['delta','file_feed'].includes(tbl.group)) { total++; if (!bq.tableDesc) issues.push({ table: key, type: 'FORMAT', detail: 'Missing table desc' }); else pass++; }
  if (['REGEX','SEQUENCEFILE','RCFILE','JSON'].includes(tbl.format)) { total++; if (!bq.tableDesc) issues.push({ table: key, type: 'SPEC_FORMAT', detail: 'Missing desc' }); else pass++; }
}

console.log('=== AUDIT RESULTS ===');
console.log(`Total: ${total} | Passed: ${pass} | Failed: ${issues.length}\n`);
if (issues.length > 0) {
  const byType = {};
  for (const i of issues) { (byType[i.type] = byType[i.type] || []).push(i); }
  for (const [t, items] of Object.entries(byType).sort()) {
    console.log(`── ${t} (${items.length}) ──`);
    for (const i of items) console.log(`  ✗ ${i.table}: ${i.detail}`);
  }
  process.exit(1);
} else {
  console.log('✓ All checks passed.');
}
