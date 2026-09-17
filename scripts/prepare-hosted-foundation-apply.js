import { execFileSync } from 'node:child_process';
import { validateHostedIdentity, verifyFoundationFiles, parseMigrationList } from './foundation-candidate-contract.js';

const execute = process.argv.includes('--execute');
const target = validateHostedIdentity({ mode: 'acceptance' });
const candidate = verifyFoundationFiles();
const expectedStart = process.env.FOUNDATION_EXPECTED_START_HEAD?.trim();
if (!['empty', '00053'].includes(expectedStart)) throw new Error('FOUNDATION_EXPECTED_START_HEAD must be empty or 00053');

const runSupabase = (args, options = {}) => process.platform === 'win32'
  ? execFileSync(process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', ['/d', '/s', '/c', `npx --yes supabase@latest ${args.join(' ')}`], options)
  : execFileSync('npx', ['--yes', 'supabase@latest', ...args], options);
const list = runSupabase(['migration', 'list', '--project-ref', target.ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const versions = parseMigrationList(list);
const actualHead = versions.at(-1) || 'empty';
if (actualHead !== expectedStart) throw new Error(`FOUNDATION_START_HEAD_MISMATCH: expected=${expectedStart} actual=${actualHead}`);

const dryRun = runSupabase(['db', 'push', '--project-ref', target.ref, '--include-all', '--dry-run'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const foundationTail = ['00054', '00055', '00056', '000565', '00057', '00058'];
const expectedPending = expectedStart === 'empty'
  ? [...Array.from({ length: 54 }, (_, index) => String(index).padStart(5, '0')), ...foundationTail]
  : foundationTail;
const dryVersions = parseMigrationList(dryRun).filter(version => version <= '00058');
if (JSON.stringify(dryVersions) !== JSON.stringify(expectedPending)) {
  throw new Error(`FOUNDATION_DRY_RUN_SET_MISMATCH: ${dryVersions.join(',')}`);
}
if (/cloud[_ -]?sms|sms_dispatch_configuration|claim_cloud_sms_batch/i.test(dryRun)) throw new Error('CLOUD_SMS_PRESENT_IN_DRY_RUN');

console.log(JSON.stringify({ pass: true, execute, target, actualHead, expectedPending, candidate, dryRunVerified: true }, null, 2));
if (!execute) process.exit(0);
if (process.env.FOUNDATION_APPLY_CONFIRMATION !== `APPLY_FOUNDATION_TO_${target.ref}`) throw new Error('FOUNDATION_APPLY_CONFIRMATION_INVALID');
runSupabase(['db', 'push', '--project-ref', target.ref, '--include-all'], { stdio: 'inherit' });
const afterList = runSupabase(['migration', 'list', '--project-ref', target.ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const finalHead = parseMigrationList(afterList).at(-1);
if (finalHead !== '00058') throw new Error(`FOUNDATION_FINAL_HEAD_MISMATCH: ${finalHead || 'empty'}`);
console.log(JSON.stringify({ pass: true, applied: true, project_ref: target.ref, final_head: finalHead, next_required_step: 'hosted-foundation-candidate-proof.sql' }, null, 2));
