#!/usr/bin/env node
/**
 * audit_ddl.mjs — Comprehensive audit of BigQuery DDL files against
 * manifests/tables.yaml and Hive source DDL.
 *
 * Checks:
 *  1. Column count parity (data cols + inlined partition cols)
 *  2. All 68 Hive column COMMENTs preserved as OPTIONS(description=...)
 *  3. Type mappings correct
 *  4. Partition column type changes correct
 *  5. Multi-column partitions correctly demote second column
 *  6. CLUSTERED BY → CLUSTER BY
 *  7. ACID tables have no NOT NULL
 *  8. SCD-2 surrogate key descriptions include TO_HEX(MD5(...))
 *  9. Format-specific tables have table-level OPTIONS(description=...)
 *
 * Run: cd /workspace/project && node scripts/audit_ddl.mjs
 */
import { readFileSync, existsSync } from 'fs';
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
    if (nm) { if (cur) tables.push(cur); cur = { name:nm[1], db:null, group:null, format:null, partition:[], bucketing:null, columns:[] }; inCols=false; continue; }
    if (!cur) continue;
    const db = t.match(/^\s{4}db:\s*(\S+)/);        if (db) { cur.db=db[1]; continue; }
    const gr = t.match(/^\s{4}group:\s*(\S+)/);      if (gr) { cur.group=gr[1]; continue; }
    const fm = t.match(/^\s{4}format:\s*(\S+)/);     if (fm) { cur.format=fm[1]; continue; }
    const pt = t.match(/^\s{4}partition:\s*\[(.+)\]/);
    if (pt) { cur.partition = pt[1].split(',').map(s => { const [n,tp] = s.trim().split(':'); return {name:n.trim(),type:tp?tp.trim():'STRING'}; }); continue; }
    const bk = t.match(/^\s{4}bucketing:\s*\{\s*by:\s*(\w+),\s*buckets:\s*(\d+)\s*\}/);
    if (bk) { cur.bucketing={by:bk[1],buckets:+bk[2]}; continue; }
    if (t.match(/^\s{4}columns:\s*$/)) { inCols=true; continue; }
    if (inCols) {
      const cs = t.match(/^\s{6}- (\w[\w.]*:\S+)/);
      if (cs) { const p=cs[1].split(':'); cur.columns.push({name:p[0],type:p[1],tags:p.slice(2).join(':').split(',').filter(Boolean)}); continue; }
      const cm = t.match(/^\s{6}-\s*\{name:\s*(\w+),\s*type:\s*(.+?)(?:,\s*tags:\s*\[([^\]]*)\])?\s*\}/);
      if (cm) { cur.columns.push({name:cm[1],type:cm[2].replace(/["']/g,'').trim(),tags:cm[3]?cm[3].split(',').map(s=>s.trim()):[]}); continue; }
      if (t.match(/^\s{4}\w/) || t.match(/^\s{2}-/) || t.match(/^[a-z]/)) inCols=false;
    }
  }
  if (cur) tables.push(cur);
  return tables;
}

// ─── Parse Hive COMMENTs ──────────────────────────────────────────────────────
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

// ─── Parse BQ DDL ─────────────────────────────────────────────────────────────
function parseBqDdl(filepath) {
  if (!existsSync(filepath)) return null;
  const text = readFileSync(filepath, 'utf8');
  const codeLines = text.split('\n').filter(l => !l.trim().startsWith('--'));
  const code = codeLines.join('\n');
  const result = { columns:[], partition:null, cluster:null, tableDescription:null, hasNotNull:false };
  const createMatch = code.match(/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+\S+\s*\(/i);
  if (!createMatch) return result;
  const startIdx = code.indexOf('(', code.indexOf(createMatch[0]));
  let depth=0, endIdx=-1;
  for (let i=startIdx; i<code.length; i++) { if(code[i]==='(')depth++; if(code[i]===')'){depth--;if(depth===0){endIdx=i;break;}} }
  if (endIdx<0) return result;
  const colBlock = code.substring(startIdx+1, endIdx);
  const afterBlock = code.substring(endIdx+1);
  // Split columns at depth-0 commas, respecting quotes (handles \' and '' escapes)
  const colStrings = []; let current='', d=0, inStr=false;
  for (let i=0; i<colBlock.length; i++) {
    const ch = colBlock[i];
    if(ch==="'"&&!inStr){inStr=true;current+=ch;continue;}
    if(ch==="'"&&inStr){
      // Handle \' backslash escape
      if(i>0&&colBlock[i-1]==='\\'){current+=ch;continue;}
      // Handle '' double-quote escape
      if(colBlock[i+1]==="'"){current+="''";i++;continue;}
      inStr=false;current+=ch;continue;
    }
    if(inStr){current+=ch;continue;}
    if(ch==='<'||ch==='(')d++; if(ch==='>'||ch===')')d--;
    if(ch===','&&d===0){if(current.trim())colStrings.push(current.trim());current='';}else{current+=ch;}
  }
  if(current.trim())colStrings.push(current.trim());
  for (const cs of colStrings) {
    let s=cs, description=null;
    // Extract OPTIONS(description='...') handling both \' and '' escapes
    const optStart = s.search(/OPTIONS\s*\(/i);
    if(optStart>=0){
      const descMatch = s.substring(optStart).match(/OPTIONS\s*\(\s*description\s*=\s*'/i);
      if(descMatch){
        const dsp=optStart+descMatch.index+descMatch[0].length;
        let desc='',de=-1;
        for(let j=dsp;j<s.length;j++){
          if(s[j]==="'"&&j>0&&s[j-1]==='\\'){desc+="'";continue;}
          if(s[j]==="'"){if(s[j+1]==="'"){desc+="'";j++;continue;}de=j;break;}
          if(s[j]==='\\'&&j+1<s.length&&s[j+1]==="'"){continue;}
          desc+=s[j];
        }
        if(de>=0){description=desc;const foe=s.indexOf(')',de+1)+1;s=(s.substring(0,optStart)+s.substring(foe)).trim();}
      }
    }
    const colMatch = s.match(/^\s*(\w+)\s+(.+?)\s*$/);
    if(colMatch){const type=colMatch[2].trim();if(type.includes('NOT NULL'))result.hasNotNull=true;result.columns.push({name:colMatch[1],type,description});}
  }
  const partMatch = afterBlock.match(/PARTITION\s+BY\s+(.+?)(?:\n|;|$)/im);
  if(partMatch) result.partition = partMatch[1].trim().replace(/;$/,'');
  const clusterMatch = afterBlock.match(/CLUSTER\s+BY\s+([^;\n]+)/i);
  if(clusterMatch) result.cluster = clusterMatch[1].trim().replace(/;$/,'');
  const tblOptMatch = afterBlock.match(/OPTIONS\s*\(\s*description\s*=\s*'([^']*)'\s*\)/i);
  if(tblOptMatch) result.tableDescription = tblOptMatch[1];
  return result;
}

// ─── Type mapping ─────────────────────────────────────────────────────────────
function mapHiveType(t) {
  const u = t.toUpperCase().trim();
  if(u==='BIGINT')return'INT64'; if(u==='INT')return'INT64'; if(u==='SMALLINT')return'INT64';
  if(u==='STRING')return'STRING'; if(u==='BOOLEAN')return'BOOL'; if(u==='DOUBLE')return'FLOAT64';
  if(u==='TIMESTAMP')return'TIMESTAMP'; if(u==='DATE')return'DATE';
  const dm = u.match(/^DECIMAL\((\d+),(\d+)\)$/); if(dm)return`NUMERIC(${dm[1]},${dm[2]})`;
  if(u==='ARRAY<STRING>')return'ARRAY<STRING>'; if(u.startsWith('MAP<STRING,STRING>'))return'JSON';
  if(u.startsWith('ARRAY<STRUCT<')){let inner=u.slice(13,-2);inner=inner.replace(/(\w+):(STRING|INT|BIGINT|BOOLEAN|DOUBLE)/gi,(_,n,tp)=>{const m={STRING:'STRING',INT:'INT64',BIGINT:'INT64',BOOLEAN:'BOOL',DOUBLE:'FLOAT64'};return`${n} ${m[tp.toUpperCase()]||tp}`;});return`ARRAY<STRUCT<${inner}>>`;}
  return u;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
const tables = parseManifest(readFileSync(MANIFEST,'utf8'));
console.log(`Parsed ${tables.length} tables from manifest\n`);
const hiveComments = {};
for (const f of ['02-staging-sqoop-mirrors.hql','03-staging-delta-feeds.hql','04-staging-file-feeds.hql','05-ods-cleanse.hql','06-ods-delta-scd2.hql','07-ods-acid.hql','08-dm-tables.hql'])
  Object.assign(hiveComments, parseHiveComments(join(SRC_DDL_DIR,f)));
console.log(`Found ${Object.keys(hiveComments).length} Hive column COMMENTs\n`);

const issues = []; let totalChecks=0, passCount=0;

for (const tbl of tables) {
  const bqDir = tbl.db==='staging'?'staging':tbl.db==='ods'?'ods':'dm';
  const bqFile = join(BQ_DDL_DIR, bqDir, `${tbl.name}.sql`);
  totalChecks++;
  if(!existsSync(bqFile)){issues.push({table:tbl.name,check:'FILE_EXISTS',detail:`Missing ${bqFile}`});continue;}
  passCount++;
  const bq = parseBqDdl(bqFile);
  if(!bq||bq.columns.length===0){issues.push({table:tbl.name,check:'PARSE',detail:'0 columns parsed'});continue;}
  const bqMap = {}; for(const c of bq.columns) bqMap[c.name]=c;

  // 1. Column count
  totalChecks++;
  const expected = tbl.columns.length + tbl.partition.length;
  if(bq.columns.length!==expected){issues.push({table:tbl.name,check:'COL_COUNT',detail:`expected ${expected} got ${bq.columns.length}`});}else{passCount++;}

  // 2. Comment preservation
  for(const col of tbl.columns){
    const key=`${tbl.name}.${col.name}`;const hc=hiveComments[key];if(!hc)continue;
    totalChecks++;const bc=bqMap[col.name];
    if(!bc){issues.push({table:tbl.name,check:'COMMENT_COL_MISSING',detail:col.name});continue;}
    if(!bc.description){issues.push({table:tbl.name,check:'COMMENT_NOT_PRESERVED',detail:`${col.name}: '${hc}'`});}else{passCount++;}
  }

  // 3. Type mapping
  for(const col of tbl.columns){
    totalChecks++;const bc=bqMap[col.name];
    if(!bc){issues.push({table:tbl.name,check:'COL_MISSING',detail:col.name});continue;}
    const exp=mapHiveType(col.type).replace(/\s+/g,' ').toUpperCase();
    const act=bc.type.replace(/\s+/g,' ').toUpperCase();
    if(exp!==act){
      if(exp.startsWith('ARRAY<STRUCT<')&&act.startsWith('ARRAY<STRUCT<')){
        const a=exp.toLowerCase().replace(/\s+/g,'').replace(/,/g,', ');
        const b=act.toLowerCase().replace(/\s+/g,'').replace(/,/g,', ');
        if(a===b){passCount++;continue;}
      }
      issues.push({table:tbl.name,check:'TYPE_MISMATCH',detail:`${col.name}: exp ${mapHiveType(col.type)} got ${bc.type}`});
    }else{passCount++;}
  }

  // 4. Partition column types
  for(const pc of tbl.partition){
    totalChecks++;let bqName=pc.name;if(pc.name==='extract_ts')bqName='extract_date';
    const bc=bqMap[bqName];
    if(!bc){issues.push({table:tbl.name,check:'PART_MISSING',detail:`${pc.name}→${bqName}`});continue;}
    let expType;
    if(['load_date','feed_date','snapshot_date','event_date','call_date','sched_date'].includes(pc.name)||pc.name==='extract_ts')expType='DATE';
    else if(['work_month','period_month','swap_month','event_month'].includes(pc.name))expType='DATE';
    else if(['eff_from_year','date_key','week_start_key'].includes(pc.name))expType='INT64';
    else if(['channel','site_code','client_code'].includes(pc.name))expType='STRING';
    else expType=mapHiveType(pc.type);
    if(bc.type!==expType){issues.push({table:tbl.name,check:'PART_TYPE',detail:`${bqName}: exp ${expType} got ${bc.type}`});}else{passCount++;}
  }

  // 5. Multi-col partitions
  if(tbl.partition.length>1){
    totalChecks++;
    let demoted;
    if(tbl.partition[0].name==='client_code')demoted='client_code';
    else if(tbl.partition[1].name==='site_code')demoted='site_code';
    else if(tbl.partition[1].name==='channel')demoted='channel';
    else demoted=tbl.partition[1].name;
    if(!bq.cluster||!bq.cluster.toLowerCase().includes(demoted.toLowerCase())){
      issues.push({table:tbl.name,check:'DEMOTED_NOT_CLUSTERED',detail:`${demoted} not in CLUSTER BY`});
    }else{passCount++;}
  }

  // 6. CLUSTERED BY → CLUSTER BY
  if(tbl.bucketing){
    totalChecks++;
    if(!bq.cluster||!bq.cluster.toLowerCase().includes(tbl.bucketing.by.toLowerCase())){
      issues.push({table:tbl.name,check:'BUCKET_CLUSTER',detail:`${tbl.bucketing.by} missing`});
    }else{passCount++;}
  }

  // 7. ACID — no NOT NULL, has CLUSTER BY
  if(tbl.group==='acid'){
    totalChecks++;if(bq.hasNotNull){issues.push({table:tbl.name,check:'ACID_NOT_NULL',detail:'has NOT NULL'});}else{passCount++;}
    totalChecks++;if(!bq.cluster){issues.push({table:tbl.name,check:'ACID_NO_CLUSTER',detail:'missing CLUSTER BY'});}else{passCount++;}
  }

  // 8. SCD-2 surrogate key descriptions
  if(tbl.group==='scd2'){
    totalChecks++;const sk=tbl.columns.find(c=>c.name.endsWith('_history_id'));
    if(sk){const bc=bqMap[sk.name];
      if(!bc||!bc.description||!bc.description.includes('TO_HEX(MD5(')){
        issues.push({table:tbl.name,check:'SCD2_DESC',detail:`${sk.name} missing TO_HEX(MD5(...))`});
      }else{passCount++;}
    }
  }

  // 9. Format-specific tables
  if(['TEXTFILE_PIPE','TEXTFILE_CSV','JSON','REGEX','SEQUENCEFILE','RCFILE'].includes(tbl.format)){
    totalChecks++;
    if(!bq.tableDescription){issues.push({table:tbl.name,check:'FORMAT_DESC',detail:`${tbl.format} missing table description`});}else{passCount++;}
  }

  // 10. Epoch staging=INT64, ODS/DM=TIMESTAMP
  for(const col of tbl.columns){
    const tags=col.tags||[];
    if(tags.some(t=>['epoch_sec','epoch_ms','lie_ms','ora_str'].includes(t))&&tbl.db==='staging'){
      totalChecks++;const bc=bqMap[col.name];if(!bc)continue;
      const exp=col.type==='STRING'?'STRING':'INT64';
      if(bc.type!==exp){issues.push({table:tbl.name,check:'EPOCH_STAGING',detail:`${col.name}: exp ${exp} got ${bc.type}`});}else{passCount++;}
    }
    if(col.type==='TIMESTAMP'&&['ods','dm'].includes(tbl.db)){
      totalChecks++;const bc=bqMap[col.name];if(!bc)continue;
      if(bc.type!=='TIMESTAMP'){issues.push({table:tbl.name,check:'EPOCH_ODS',detail:`${col.name}: not TIMESTAMP`});}else{passCount++;}
    }
  }
}

console.log('='.repeat(70));
console.log(`AUDIT: ${totalChecks} checks, ${passCount} passed, ${issues.length} issues`);
console.log('='.repeat(70));
if(issues.length===0){console.log('\n✅ ALL CHECKS PASSED');}
else{const byCheck={};for(const i of issues){(byCheck[i.check]||(byCheck[i.check]=[])).push(i);}
for(const[c,items]of Object.entries(byCheck).sort()){console.log(`\n── ${c} (${items.length}) ──`);for(const i of items)console.log(`  ✗ ${i.table}: ${i.detail}`);}}

console.log(`\n── DECIMAL pairs: ${[...new Set(tables.flatMap(t=>t.columns.filter(c=>c.type.match(/DECIMAL/i)).map(c=>{const m=c.type.match(/DECIMAL\((\d+),(\d+)\)/i);return m?`NUMERIC(${m[1]},${m[2]})`:null;}).filter(Boolean)))].sort().join(', ')} ──`);
process.exit(issues.length>0?1:0);
