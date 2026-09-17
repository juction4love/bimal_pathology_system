import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = path.join(root, 'src/types/supabase.generated.ts');
const executable = process.platform === 'win32' ? (process.env.ComSpec || 'cmd.exe') : 'npx';
const args = process.platform === 'win32'
  ? ['/d', '/s', '/c', 'npx --yes supabase gen types typescript --linked --schema public']
  : ['--yes', 'supabase', 'gen', 'types', 'typescript', '--linked', '--schema', 'public'];
const generated = spawnSync(executable, args, {
  cwd: root,
  encoding: 'utf8',
  maxBuffer: 16 * 1024 * 1024,
});

if (generated.status !== 0) {
  process.stderr.write(generated.stderr || generated.stdout || generated.error?.message || 'Unknown Supabase CLI error.');
  throw new Error('Supabase linked-schema type generation failed.');
}
assert.match(generated.stdout, /export type Database =/);
assert.doesNotMatch(generated.stdout, /service[_-]?role|sb_secret_|SPARROW/i);
const canonical = generated.stdout.replaceAll('\r\n', '\n');

if (process.argv.includes('--check')) {
  assert.equal(fs.readFileSync(target, 'utf8').replaceAll('\r\n', '\n'), canonical, 'Generated Supabase types are stale. Run npm run types:generate.');
  console.log('Generated Supabase types match the linked public schema.');
} else {
  fs.writeFileSync(target, canonical, 'utf8');
  console.log(`Generated Supabase types: ${path.relative(root, target).replaceAll('\\', '/')}`);
}
