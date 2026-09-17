import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const PRODUCTION_REF = 'rncjxstujioagcezvfkb';
export const QUARANTINED_STAGING_REF = 'qvuidmgddjoircheapzk';
export const PERMANENT_STAGING_REF = 'ilcnctiaumrjbnlmnise';
export const APPROVED = Object.freeze({
  '00054_shared_catalogue_collection_and_bpdc_foundation.sql': '8b1d48c52e1d92250b23a0e8836f34bbfc9596b5ba603f4cc85e023b0e38e3eb',
  '00055_foundation_rpc_and_sample_traceability_contracts.sql': 'f1e4ba6e4e7db5d5a0ecef7bc50e2602653abb75f03d4d2d636a619169e8e9cd',
  '00056_foundation_result_readiness_and_revision.sql': '72265a16fb64a17ebb1ef259b42d90d4143d3e547ee2805ed5dffd6b8839e3bf',
  '000565_legacy_hosted_privilege_preconvergence.sql': '1a96d5ca2e038875c6456a29fe31b213a5a2f6c4c8c053f29059957865063116',
  '00057_hosted_privilege_convergence.sql': '6f20781900c90f668204330c854b28e94cd17606d2a1e9f78b1d12a1d708e23d',
  '00058_foundation_result_initialization_contract.sql': '90e0546dd6c60c27d9f552d506c9f7f624068f665fb87abb286906690fd66fd6',
});
export const APPROVED_SET_SHA256 = '4cd33b27dda7751d2776d7fe19888c12c4b05978aec802a5fb509b7fc17eb22e';

const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
const executableSql = value => value
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/--[^\r\n]*/g, ' ')
  .replace(/'(?:''|[^'])*'/g, "''");

export function verifyFoundationFiles(root = process.cwd()) {
  const dir = path.join(root, 'supabase', 'migrations');
  const versionOf = name => name.slice(0, name.indexOf('_'));
  const files = fs.readdirSync(dir)
    .filter(name => /^\d{5,}_.+\.sql$/.test(name))
    .sort((left, right) => versionOf(left).localeCompare(versionOf(right)) || left.localeCompare(right));
  // This module seals the historical foundation subset only. Later accepted
  // migrations are verified by their own candidate contracts and must not make
  // the immutable 00054-00058 proof appear corrupt.
  const pending = files.filter(name => versionOf(name) > '00053' && versionOf(name) <= '00058');
  if (JSON.stringify(pending) !== JSON.stringify(Object.keys(APPROVED))) {
    throw new Error(`FOUNDATION_MIGRATION_SET_MISMATCH: ${pending.join(',')}`);
  }
  for (const [name, expected] of Object.entries(APPROVED)) {
    const body = fs.readFileSync(path.join(dir, name));
    const actual = sha256(body);
    if (actual !== expected) throw new Error(`FOUNDATION_MIGRATION_CHECKSUM_MISMATCH: ${name} ${actual}`);
    if (/cloud[_ -]?sms|sms_dispatch_configuration|claim_cloud_sms_batch/i.test(executableSql(body.toString('utf8')))) {
      throw new Error(`CLOUD_SMS_FORBIDDEN_IN_FOUNDATION: ${name}`);
    }
  }
  const migrationSet = crypto.createHash('sha256');
  for (const name of files.filter(name => versionOf(name) <= '00058')) {
    migrationSet.update(name);
    migrationSet.update('\0');
    migrationSet.update(fs.readFileSync(path.join(dir, name)));
    migrationSet.update('\0');
  }
  const migrationSetSha256 = migrationSet.digest('hex');
  if (migrationSetSha256 !== APPROVED_SET_SHA256) {
    throw new Error(`FOUNDATION_MIGRATION_SET_CHECKSUM_MISMATCH: ${migrationSetSha256}`);
  }
  return { pending, checksums: APPROVED, migrationSetSha256, cloudSmsExcluded: true };
}

export function validateHostedIdentity({ mode }) {
  const ref = process.env.FOUNDATION_PROJECT_REF?.trim();
  const url = process.env.FOUNDATION_SUPABASE_URL?.trim();
  const environment = process.env.FOUNDATION_TARGET_ENVIRONMENT?.trim();
  if (!ref || !/^[a-z]{20}$/.test(ref)) throw new Error('FOUNDATION_PROJECT_REF_REQUIRED');
  if (ref === QUARANTINED_STAGING_REF) throw new Error('QUARANTINED_STAGING_REFUSED');
  if (mode === 'acceptance' && ref !== PERMANENT_STAGING_REF) throw new Error('PERMANENT_STAGING_PROJECT_REF_MISMATCH');
  if (mode === 'acceptance' && ref === PRODUCTION_REF) throw new Error('PRODUCTION_REFUSED_FOR_ACCEPTANCE');
  if (mode === 'production' && ref !== PRODUCTION_REF) throw new Error('PRODUCTION_PROJECT_REF_MISMATCH');
  const requiredEnvironment = mode === 'production' ? 'production-cutover' : 'isolated-acceptance';
  if (environment !== requiredEnvironment) throw new Error(`FOUNDATION_TARGET_ENVIRONMENT_MUST_BE_${requiredEnvironment}`);
  const parsed = new URL(url || 'invalid:');
  if (parsed.protocol !== 'https:' || parsed.hostname !== `${ref}.supabase.co` || parsed.pathname !== '/') {
    throw new Error('FOUNDATION_SUPABASE_URL_PROJECT_MISMATCH');
  }
  const confirmation = process.env.FOUNDATION_TARGET_CONFIRMATION;
  const requiredConfirmation = mode === 'production'
    ? `I_CONFIRM_FOUNDATION_PRODUCTION_${PRODUCTION_REF}`
    : `I_CONFIRM_SYNTHETIC_ACCEPTANCE_${ref}`;
  if (confirmation !== requiredConfirmation) throw new Error('FOUNDATION_TARGET_CONFIRMATION_INVALID');
  return { ref, url: parsed.origin, environment, mode };
}

export function parseMigrationList(output) {
  const jsonLine = output.split(/\r?\n/).reverse().find(line => line.trim().startsWith('{'));
  if (jsonLine) {
    const parsed = JSON.parse(jsonLine);
    if (Array.isArray(parsed.migrations) && parsed.migrations.every(row => typeof row === 'string')) {
      return [...new Set(parsed.migrations.map(name => name.slice(0, name.indexOf('_'))))].sort();
    }
    if (Array.isArray(parsed.migrations)) {
      return [...new Set(parsed.migrations.map(row => row.remote).filter(Boolean))].sort();
    }
  }
  const rows = [...output.matchAll(/\b(\d{5,})(?=_|\b)/g)].map(match => match[1]);
  return [...new Set(rows)].sort();
}
