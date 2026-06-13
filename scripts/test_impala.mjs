import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const hive = require('hive-driver');
const { TCLIService, TCLIService_types } = hive.thrift;
const utils = new hive.HiveUtils(TCLIService_types);

async function q(s, sql) {
  const op = await s.executeStatement(sql, { runAsync: true });
  await utils.waitUntilReady(op, false, () => {});
  await utils.fetchAll(op, 1);
  const r = utils.getResult(op).getValue() ?? [];
  await op.close();
  return r;
}

(async () => {
  const c = new hive.HiveClient(TCLIService, TCLIService_types);
  const auth = process.env.TESTING_HIVE_AUTH === 'nosasl'
    ? new hive.auth.NoSaslAuthentication()
    : new hive.auth.PlainTcpAuthentication({ username: process.env.TESTING_USER || 'impala', password: '' });
  const conn = await c.connect(
    { host: process.env.TESTING_HOST, port: Number(process.env.TESTING_PORT) },
    new hive.connections.TcpConnection(), auth
  );
  const s = await conn.openSession({ client_protocol: TCLIService_types.TProtocolVersion.HIVE_CLI_SERVICE_PROTOCOL_V10 });

  const dbs = (await q(s, 'SHOW DATABASES')).map(r => Object.values(r)[0]);
  console.log('DATABASES:', dbs.join(', '));

  // Try creating a test DB and table
  try { await q(s, 'CREATE DATABASE IF NOT EXISTS qa_staging'); } catch(e) { console.log('create db err:', e.message); }
  try {
    await q(s, 'CREATE TABLE IF NOT EXISTS qa_staging.test_probe (id INT)');
    const desc = await q(s, 'DESCRIBE qa_staging.test_probe');
    console.log('DESCRIBE test_probe:', JSON.stringify(desc));
    await q(s, 'DROP TABLE IF EXISTS qa_staging.test_probe');
  } catch(e) { console.log('probe err:', e.message); }

  await s.close();
  process.exit(0);
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
