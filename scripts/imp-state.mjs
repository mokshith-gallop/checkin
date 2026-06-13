import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const hive = require('hive-driver');
const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);
const H = 'IMPALA';
async function q(s, sql){const op=await s.executeStatement(sql,{runAsync:true});await utils.waitUntilReady(op,false,()=>{});await utils.fetchAll(op,1);const r=utils.getResult(op).getValue()??[];await op.close();return r;}
(async()=>{
  const c=new hive.HiveClient(TCLIService,TCLIService_types);
  const auth=process.env[H+'_HIVE_AUTH']==='nosasl'?new hive.auth.NoSaslAuthentication():new hive.auth.PlainTcpAuthentication({username:process.env[H+'_USER']||'impala',password:''});
  const conn=await c.connect({host:process.env[H+'_HOST'],port:Number(process.env[H+'_PORT'])},new hive.connections.TcpConnection(),auth);
  const s=await conn.openSession({client_protocol:TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10});
  const dbs=(await q(s,'SHOW DATABASES')).map(r=>Object.values(r)[0]);
  console.log('DATABASES:', dbs.join(', '));
  for(const db of dbs){ if(/builtin/.test(db))continue; const t=(await q(s,'SHOW TABLES IN `'+db+'`')).map(r=>Object.values(r)[0]); console.log(' '+db+': '+(t.length?t.join(', '):'(empty)')); }
  await s.close(); process.exit(0);
})().catch(e=>{console.error('ERR',e.message);process.exit(1);});
