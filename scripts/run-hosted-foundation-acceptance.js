import { execFileSync } from 'node:child_process';
import { validateHostedIdentity, verifyFoundationFiles } from './foundation-candidate-contract.js';

const target = validateHostedIdentity({ mode: 'acceptance' });
verifyFoundationFiles();
if (process.env.FOUNDATION_ACCEPTANCE_RUN_CONFIRMATION !== `RUN_SYNTHETIC_ACCEPTANCE_ON_${target.ref}`) {
  throw new Error('FOUNDATION_ACCEPTANCE_RUN_CONFIRMATION_INVALID');
}
if (process.env.STAGING_PROJECT_REF !== target.ref || process.env.STAGING_SUPABASE_URL !== target.url) {
  throw new Error('STAGING_* runtime aliases do not match the guarded acceptance target.');
}
if (process.env.STAGING_EXPECTED_MIGRATION_HEAD !== '00058') throw new Error('Hosted result-initialization acceptance requires head 00058');
const node = process.execPath;
const suites = [
  'scripts/staging-phase2-catalogue-runtime.js',
  'scripts/staging-phase2-billing-runtime.js',
  'scripts/hosted-foundation-auth-rpc-acceptance.js',
  'scripts/staging-phase2-clinical-lifecycle.js',
  'scripts/staging-phase2-signoff-concurrency.js',
  'scripts/staging-critical-amendment-runtime.js',
];
for (const suite of suites) {
  console.log(`[FOUNDATION HOSTED ACCEPTANCE] ${suite}`);
  execFileSync(node, [suite], { cwd: process.cwd(), env: process.env, stdio: 'inherit' });
}
console.log(JSON.stringify({ pass: true, project_ref: target.ref, suites, cloud_sms_suite_executed: false, sparrow_send_attempted: false }, null, 2));
