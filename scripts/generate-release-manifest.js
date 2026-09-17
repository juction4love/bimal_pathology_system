import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const migrationsDir = path.join(root, 'supabase/migrations');
const expectedProjectRef = 'rncjxstujioagcezvfkb';
const expectedSupabaseOrigin = `https://${expectedProjectRef}.supabase.co`;
const expectedPublicAppOrigin = 'https://lis.bimalpathology.com.np';
const checkOnly = process.argv.includes('--check');
const sourceRoots = [
  'src',
  'public',
  'index.html',
  'vite.config.ts',
  'playwright.production.config.js',
  'package.json',
  'package-lock.json',
  'tsconfig.json',
  'tsconfig.app.json',
  'tsconfig.node.json',
  'scripts/generate-release-manifest.js',
  'scripts/seal-release-artifact.js',
  'scripts/verify-release-determinism.js',
  'scripts/verify-release-preview.js',
];

function filesUnder(relative) {
  const absolute = path.join(root, relative);
  if (!fs.existsSync(absolute)) throw new Error(`Release source is missing: ${relative}`);
  if (!fs.statSync(absolute).isDirectory()) return [absolute];
  return fs.readdirSync(absolute, { withFileTypes: true })
    .flatMap((entry) => filesUnder(path.join(relative, entry.name)));
}

function parseEnvFile(file) {
  if (!fs.existsSync(file)) throw new Error('.env.production is required for the production release build.');
  const values = {};
  for (const rawLine of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator <= 0) continue;
    const name = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[name] = value;
  }
  return values;
}

function requireEffectiveBuildValue(name, fileValues) {
  const value = (process.env[name] ?? fileValues[name])?.trim();
  if (!value) throw new Error(`${name} is required for the production release build.`);
  return value;
}

function exactOrigin(name, rawValue) {
  let parsed;
  try {
    parsed = new URL(rawValue);
  } catch {
    throw new Error(`${name} must be an absolute URL.`);
  }
  if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== '/') {
    throw new Error(`${name} must contain only an HTTPS origin.`);
  }
  return parsed.origin;
}

function assetNamespaceForVersion(version) {
  const normalized = version.replace(/[^0-9A-Za-z]+/g, '_').replace(/^_+|_+$/g, '');
  if (!normalized) throw new Error('Frontend version cannot produce an empty asset namespace.');
  return `r${normalized}`;
}

const productionFileValues = parseEnvFile(path.join(root, '.env.production'));
const effectiveBuildConfig = {
  VITE_SUPABASE_URL: requireEffectiveBuildValue('VITE_SUPABASE_URL', productionFileValues),
  VITE_SUPABASE_ANON_KEY: requireEffectiveBuildValue('VITE_SUPABASE_ANON_KEY', productionFileValues),
  VITE_PUBLIC_APP_URL: requireEffectiveBuildValue('VITE_PUBLIC_APP_URL', productionFileValues),
};
const supabaseOrigin = exactOrigin('VITE_SUPABASE_URL', effectiveBuildConfig.VITE_SUPABASE_URL);
const publicAppOrigin = exactOrigin('VITE_PUBLIC_APP_URL', effectiveBuildConfig.VITE_PUBLIC_APP_URL);
if (supabaseOrigin !== expectedSupabaseOrigin) {
  throw new Error(`Refusing production build for Supabase origin ${supabaseOrigin}; expected ${expectedSupabaseOrigin}.`);
}
if (publicAppOrigin !== expectedPublicAppOrigin) {
  throw new Error(`Refusing production build for public origin ${publicAppOrigin}; expected ${expectedPublicAppOrigin}.`);
}
if (!effectiveBuildConfig.VITE_SUPABASE_ANON_KEY.startsWith('sb_publishable_') ||
    /service[_-]?role|sb_secret_/i.test(effectiveBuildConfig.VITE_SUPABASE_ANON_KEY)) {
  throw new Error('VITE_SUPABASE_ANON_KEY must be a Supabase publishable key, never a secret/service-role key.');
}

const buildConfigHash = crypto.createHash('sha256');
for (const name of Object.keys(effectiveBuildConfig).sort()) {
  buildConfigHash.update(name);
  buildConfigHash.update('\0');
  buildConfigHash.update(effectiveBuildConfig[name]);
  buildConfigHash.update('\0');
}

const sourceFiles = sourceRoots.flatMap(filesUnder)
  .filter((file) => path.basename(file) !== 'release-manifest.json')
  .sort((a, b) => a.localeCompare(b));
const sourceHash = crypto.createHash('sha256');
for (const file of sourceFiles) {
  sourceHash.update(path.relative(root, file).replaceAll('\\', '/'));
  sourceHash.update('\0');
  sourceHash.update(fs.readFileSync(file));
  sourceHash.update('\0');
}

const migrations = fs.readdirSync(migrationsDir)
  .filter((name) => /^\d+.*\.sql$/.test(name))
  .sort((left, right) => {
    const leftVersion = left.slice(0, left.indexOf('_'));
    const rightVersion = right.slice(0, right.indexOf('_'));
    return leftVersion.localeCompare(rightVersion) || left.localeCompare(right);
  });
const migrationRows = migrations.map((name) => {
  const match = /^(\d{5,})_.+\.sql$/.exec(name);
  if (!match) throw new Error(`Migration filename is not canonical: ${name}`);
  return { name, version: match[1] };
});
const duplicateVersions = migrationRows
  .map(({ version }) => version)
  .filter((version, index, versions) => versions.indexOf(version) !== index);
if (duplicateVersions.length > 0) {
  throw new Error(`Duplicate migration version(s): ${[...new Set(duplicateVersions)].join(', ')}`);
}
const migrationHead = migrationRows.at(-1)?.version || 'unknown';
const migrationHash = crypto.createHash('sha256');
for (const { name } of migrationRows) {
  migrationHash.update(name);
  migrationHash.update('\0');
  migrationHash.update(fs.readFileSync(path.join(migrationsDir, name)));
  migrationHash.update('\0');
}

const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const frontendVersion = String(packageJson.version ?? '').trim();
if (!frontendVersion || frontendVersion === '0.0.0') {
  throw new Error('package.json must contain a non-placeholder frontend version.');
}
const packageLock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
if (packageLock.version !== frontendVersion || packageLock.packages?.['']?.version !== frontendVersion) {
  throw new Error('package.json and package-lock.json frontend versions must match.');
}

const gatewayProject = fs.readFileSync(path.join(root, 'tools/sms-gateway/BimalPathology.SmsGateway.csproj'), 'utf8');
const gatewayVersion = gatewayProject.match(/<Version>([^<]+)<\/Version>/)?.[1] || 'unknown';
if (gatewayVersion !== '1.0.4') throw new Error(`Gateway version must be 1.0.4; found ${gatewayVersion}.`);

const sourceSha256 = sourceHash.digest('hex');
const migrationSha256 = migrationHash.digest('hex');
const buildConfigSha256 = buildConfigHash.digest('hex');
const assetNamespace = assetNamespaceForVersion(frontendVersion);
const manifest = {
  schemaVersion: 2,
  application: 'bimal-pathology-cloud',
  targetEnvironment: 'production',
  supabaseProjectRef: expectedProjectRef,
  publicAppOrigin,
  frontendVersion,
  assetNamespace,
  frontendSourceSha256: sourceSha256,
  frontendBuildConfigSha256: buildConfigSha256,
  migrationHead,
  migrationSha256,
  gatewayVersion,
  releaseId: `${frontendVersion}-${migrationHead}-${migrationSha256.slice(0, 8)}-${sourceSha256.slice(0, 12)}-${assetNamespace}-gateway-${gatewayVersion}`,
};

if (!checkOnly) {
  const target = path.join(root, 'public/release-manifest.json');
  fs.writeFileSync(target, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
}
console.log(`Release manifest ${checkOnly ? 'contract' : 'generated'}: ${manifest.releaseId}`);
console.log(`Release target: environment=production project_ref=${expectedProjectRef} migration_head=${migrationHead} gateway=${gatewayVersion}`);
