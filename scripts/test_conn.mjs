import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const hive = require('hive-driver');
const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);

const client = new hive.HiveClient(TCLIService, TCLIService_types);
const auth = new hive.auth.NoSaslAuthentication();
const conn = await client.connect(
  { host: process.env.TESTING_HOST, port: Number(process.env.TESTING_PORT) },
  new hive.connections.TcpConnection(), auth
);
const session = await conn.openSession({client_protocol: TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10});

async function q(sql) {
  const op = await session.executeStatement(sql, {runAsync:true});
  await utils.waitUntilReady(op, false, ()=>{});
  await utils.fetchAll(op, 1);
  const rows = utils.getResult(op).getValue() ?? [];
  await op.close();
  return rows;
}

const dbs = await q('SHOW DATABASES');
console.log('Impala OK, databases:', dbs.map(r => Object.values(r)[0]).join(', '));
await session.close();
process.exit(0);
