import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const psqlBin = 'C:/Program Files/PostgreSQL/17/bin/psql.exe';
const root = path.resolve(import.meta.dirname, '..');
const port = 54329;
const dbName = 'lis_test_00095';

console.log('[1/4] Dropping and recreating test database:', dbName);
execFileSync(psqlBin, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', `DROP DATABASE IF EXISTS lis_test_00095;`]);
  execFileSync(psqlBin, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', 'postgres', '-c', `CREATE DATABASE lis_test_00095;`], { stdio: 'inherit' });

console.log('[2/4] Applying Supabase foundation scaffold...');
execFileSync(psqlBin, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', dbName, '-f', path.join(root, 'scripts/local-foundation-supabase-scaffold.sql')], { stdio: 'inherit' });

const migrationDir = path.join(root, 'supabase/migrations');
const key = name => {
  const v = name.match(/^(\d+)_/)?.[1];
  return v === '000565' ? 56.5 : Number(v);
};
const files = fs.readdirSync(migrationDir).filter(n => n.endsWith('.sql')).sort((a, b) => key(a) - key(b) || a.localeCompare(b));
console.log(`[3/4] Replaying ${files.length} migrations from ${files[0]} through ${files.at(-1)}...`);

for (let i = 0; i < files.length; i++) {
  const file = files[i];
  process.stdout.write(`\rApplying migration ${i + 1}/${files.length}: ${file.slice(0, 45)}... `);
  try {
    execFileSync(psqlBin, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', dbName, '-v', 'ON_ERROR_STOP=1', '--single-transaction', '-f', path.join(migrationDir, file)], { stdio: 'pipe' });
  } catch (err) {
    console.error(`\nError applying ${file}:`, err.stderr?.toString() || err.message);
    process.exit(1);
  }
}
console.log('\n[3/4] All 96 migrations applied cleanly through 00095!');

console.log('[4/4] Executing Android 00095 PostgreSQL Runtime Authorization Acceptance Suite...');
execFileSync(psqlBin, ['-h', '127.0.0.1', '-p', String(port), '-U', 'postgres', '-d', dbName, '-v', 'ON_ERROR_STOP=1', '-f', path.join(root, 'scripts/android-00095-postgres-acceptance.sql')], { stdio: 'inherit' });
console.log('\n=========================================');
console.log('=== ALL RUNTIME ACCEPTANCE TESTS PASSED ===');
console.log('=========================================');