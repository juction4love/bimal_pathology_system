import {execFileSync} from'node:child_process';
import path from'node:path';
const url=process.env.LIS_TEST_DATABASE_URL;if(!url)throw new Error('LIS_TEST_DATABASE_URL is required.');
const parsed=new URL(url);if(!['127.0.0.1','localhost','::1'].includes(parsed.hostname))throw new Error('Loopback PostgreSQL is required.');
execFileSync(process.env.POSTGRES_PSQL_PATH||'psql',['--dbname',url,'-X','-f',path.resolve('scripts/report-artifact-worker-postgres-integration.sql')],{stdio:'inherit'});
