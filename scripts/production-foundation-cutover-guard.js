import { execFileSync } from 'node:child_process';
import { validateHostedIdentity, parseMigrationList } from './foundation-candidate-contract.js';
import { BASELINE_HEAD, CANDIDATE, CANDIDATE_HEAD, verifyCandidate00079 } from './candidate-00079-contract.js';

const execute = process.argv.includes('--execute');
const target = validateHostedIdentity({ mode: 'production' });
const candidate = verifyCandidate00079();
const runSupabase = (args, options = {}) => process.platform === 'win32'
  ? execFileSync(process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', ['/d', '/s', '/c', `npx --yes supabase@latest ${args.join(' ')}`], options)
  : execFileSync('npx', ['--yes', 'supabase@latest', ...args], options);
const list = runSupabase(['migration', 'list', '--project-ref', target.ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const head = parseMigrationList(list).at(-1);
if (head !== BASELINE_HEAD) throw new Error(`PRODUCTION_HEAD_MUST_BE_${BASELINE_HEAD}: ${head || 'empty'}`);
const dryRun = runSupabase(['db', 'push', '--project-ref', target.ref, '--dry-run', '--include-all'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const pending = parseMigrationList(dryRun).filter(version => version > BASELINE_HEAD);
const approvedPending = Object.keys(CANDIDATE).map(name => name.slice(0, name.indexOf('_')));
if (JSON.stringify(pending) !== JSON.stringify(approvedPending)) throw new Error(`PRODUCTION_PENDING_SET_MISMATCH: ${pending.join(',')}`);
if (/cloud[_ -]?sms|sms_dispatch_configuration|claim_cloud_sms_batch/i.test(dryRun)) throw new Error('CLOUD_SMS_PRESENT_IN_PRODUCTION_DRY_RUN');
console.log(JSON.stringify({ pass: true, execute, target, head, pending, candidate }, null, 2));
if (!execute) process.exit(0);
if (process.env.FOUNDATION_PRODUCTION_APPLY_CONFIRMATION !== `APPLY_00076_00079_TO_${target.ref}`) throw new Error('PRODUCTION_APPLY_CONFIRMATION_INVALID');
runSupabase(['db', 'push', '--project-ref', target.ref, '--include-all'], { stdio: 'inherit' });
const finalList = runSupabase(['migration', 'list', '--project-ref', target.ref], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
const finalHead = parseMigrationList(finalList).at(-1);
if (finalHead !== CANDIDATE_HEAD) throw new Error(`PRODUCTION_FINAL_HEAD_MISMATCH: ${finalHead || 'empty'}`);
