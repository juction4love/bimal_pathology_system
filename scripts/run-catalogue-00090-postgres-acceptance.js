import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const url=process.env.LIS_TEST_DATABASE_URL;
if(!url)throw new Error('LIS_TEST_DATABASE_URL is required.');
const parsed=new URL(url);
if(!['127.0.0.1','localhost','::1'].includes(parsed.hostname))throw new Error('Loopback PostgreSQL only.');
execFileSync('psql',['--dbname',url,'-X','-f',fileURLToPath(new URL('./catalogue-00090-postgres-acceptance.sql',import.meta.url))],{stdio:'inherit'});
