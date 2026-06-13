import { createRequire } from 'module';
const require = createRequire('/opt/workspace-mcp/node_modules/.package-lock.json');
const { BigQuery } = require('@google-cloud/bigquery');
const { OAuth2Client } = require('google-auth-library');

const authClient = new OAuth2Client();
authClient.setCredentials({ access_token: process.env.BIGQUERY_TEST_BQ_TOKEN });
const bq = new BigQuery({ projectId: process.env.BIGQUERY_TEST_BQ_PROJECT, authClient });

const ds = process.env.BIGQUERY_TEST_BQ_DATASETS;
console.log('BQ project:', process.env.BIGQUERY_TEST_BQ_PROJECT, 'dataset:', ds);

const [tables] = await bq.dataset(ds).getTables();
console.log('BQ OK, tables in', ds + ':', tables.map(t => t.id).join(', ') || '(empty)');
process.exit(0);
