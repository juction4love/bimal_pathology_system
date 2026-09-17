import { execFileSync } from 'node:child_process';
import path from 'node:path';

const url=process.env.LIS_TEST_DATABASE_URL;
if(!url) throw new Error('LIS_TEST_DATABASE_URL is required for the isolated PostgreSQL regression.');
const parsed=new URL(url);
if(!['127.0.0.1','localhost','::1'].includes(parsed.hostname)) throw new Error('The PostgreSQL integration runner refuses non-loopback databases.');
const psql=process.env.POSTGRES_PSQL_PATH||'psql';
execFileSync(psql,['--dbname',url,'-X','-f',path.resolve('scripts/two-role-postgres-integration.sql')],{stdio:'inherit'});
