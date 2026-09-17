import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const url = process.env.LIS_TEST_DATABASE_URL;
if (!url) {
  console.log('LIS_TEST_DATABASE_URL not set; skipping local postgres execution.');
  process.exit(0);
}
const host = new URL(url).hostname;
if (!['127.0.0.1', 'localhost', '::1'].includes(host)) {
  throw new Error('Loopback PostgreSQL only.');
}
execFileSync('psql', ['--dbname', url, '-X', '-f', fileURLToPath(new URL('./catalogue-00093-calculation-acceptance.sql', import.meta.url))], { stdio: 'inherit' });
