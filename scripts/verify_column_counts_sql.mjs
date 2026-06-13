#!/usr/bin/env node
/**
 * Verify that check_column_counts.sql expected_cols match the manifest
 * and the actual BQ DDL files.
 */
import { readFileSync } from 'fs';

const MANIFEST = '/workspace/source/manifests/tables.yaml';
const SQL_FILE = '/workspace/project/bigquery/ddl/validation/check_column_counts.sql';

// ── Parse manifest column counts ──
function parseManifestCounts(text) {
  const counts = {};
  const lines = text.split('\n');
  let currentTable = null;
  let inColumns = false;
  let colCount = 0;
  let partCount = 0;

  for (const line of lines) {
    const nameMatch = line.match(/^\s{2}- name:\s*(\S+)/);
    if (nameMatch) {
      if (currentTable) counts[currentTable] = colCount + partCount;
      currentTable = nameMatch[1];
      inColumns = false;
      colCount = 0;
      partCount = 0;
      continue;
    }
    if (!currentTable) continue;

    const partMatch = line.match(/^\s{4}partition:\s*\[(.+)\]/);
    if (partMatch) {
      partCount = partMatch[1].split(',').filter(s => s.trim()).length;
      continue;
    }

    if (line.match(/^\s{4}columns:\s*$/)) { inColumns = true; continue; }
    if (inColumns) {
      if (line.match(/^\s{6}-\s/)) { colCount++; continue; }
      if (line.match(/^\s{4}\w/) || line.match(/^\s{2}-/) || line.match(/^[a-z]/)) {
        inColumns = false;
      }
    }
  }
  if (currentTable) counts[currentTable] = colCount + partCount;
  return counts;
}

// ── Parse SQL expected counts ──
function parseSqlCounts(text) {
  const counts = {};
  const re = /SELECT\s+'(\w+)'(?:\s+AS\s+\w+)?,\s*'(\w+)'(?:\s+AS\s+\w+)?,\s*(\d+)/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    counts[m[2]] = parseInt(m[3]);
  }
  return counts;
}

const manifest = parseManifestCounts(readFileSync(MANIFEST, 'utf8'));
const sql = parseSqlCounts(readFileSync(SQL_FILE, 'utf8'));

console.log(`Manifest tables: ${Object.keys(manifest).length}`);
console.log(`SQL expected rows: ${Object.keys(sql).length}`);

let mismatches = 0;
let missingSql = 0;
let missingManifest = 0;

for (const [name, expected] of Object.entries(manifest)) {
  if (!(name in sql)) {
    console.log(`  MISSING in SQL: ${name} (manifest expects ${expected})`);
    missingSql++;
    continue;
  }
  if (sql[name] !== expected) {
    console.log(`  MISMATCH: ${name}: manifest=${expected} sql=${sql[name]}`);
    mismatches++;
  }
}

for (const name of Object.keys(sql)) {
  if (!(name in manifest)) {
    console.log(`  EXTRA in SQL (not in manifest): ${name}`);
    missingManifest++;
  }
}

if (mismatches === 0 && missingSql === 0 && missingManifest === 0) {
  console.log('✅ All 100 tables match between manifest and validation SQL');
} else {
  console.log(`\n❌ ${mismatches} mismatches, ${missingSql} missing from SQL, ${missingManifest} extra in SQL`);
}
