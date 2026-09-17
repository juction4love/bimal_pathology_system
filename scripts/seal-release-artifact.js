import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const distRoot = path.join(root, 'dist');
const identityRoot = path.join(root, 'artifacts/releases');
const writeMode = process.argv.includes('--write');
const verifyMode = process.argv.includes('--verify');
if (writeMode === verifyMode) {
  throw new Error('Use exactly one mode: --write after the one final build, or --verify afterward.');
}

function filesUnder(directory) {
  return fs.readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => entry.isDirectory()
      ? filesUnder(path.join(directory, entry.name))
      : [path.join(directory, entry.name)]);
}

function readJson(file, label) {
  if (!fs.existsSync(file)) throw new Error(`${label} is missing: ${file}`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

if (!fs.existsSync(distRoot) || !fs.statSync(distRoot).isDirectory()) {
  throw new Error('dist does not exist; sealing is allowed only after the final successful build.');
}

const publicManifestPath = path.join(root, 'public/release-manifest.json');
const distManifestPath = path.join(distRoot, 'release-manifest.json');
if (!fs.existsSync(publicManifestPath) || !fs.existsSync(distManifestPath)) {
  throw new Error('Both public and dist release manifests must exist before sealing.');
}
const publicManifestBytes = fs.readFileSync(publicManifestPath);
const distManifestBytes = fs.readFileSync(distManifestPath);
assert.deepEqual(distManifestBytes, publicManifestBytes, 'dist and public release manifests must be byte-identical');
const manifest = readJson(distManifestPath, 'dist release manifest');
assert.equal(manifest.schemaVersion, 2, 'release manifest schema must be version 2');
assert.equal(manifest.targetEnvironment, 'production', 'release target must be production');
assert.equal(manifest.supabaseProjectRef, 'rncjxstujioagcezvfkb', 'release target project ref mismatch');
assert.equal(manifest.publicAppOrigin, 'https://lis.bimalpathology.com.np', 'release public origin mismatch');
assert.equal(manifest.gatewayVersion, '1.0.4', 'release Gateway version mismatch');
assert.match(manifest.releaseId, /^[0-9A-Za-z._-]+$/, 'release ID contains unsafe path characters');
assert.match(manifest.assetNamespace, /^r[0-9A-Za-z_]+$/, 'asset namespace is invalid');
const expectedReleaseId = `${manifest.frontendVersion}-${manifest.migrationHead}-${manifest.migrationSha256.slice(0, 8)}-${manifest.frontendSourceSha256.slice(0, 12)}-${manifest.assetNamespace}-gateway-${manifest.gatewayVersion}`;
assert.equal(manifest.releaseId, expectedReleaseId, 'release ID does not match its immutable source/configuration identity');
assert.equal(Object.hasOwn(manifest, 'generatedAtUtc'), false, 'volatile generation time must not be embedded in the immutable release manifest');

const distFiles = filesUnder(distRoot).sort((a, b) => a.localeCompare(b));
const treeHash = crypto.createHash('sha256');
const files = distFiles.map((file) => {
  const relativePath = path.relative(distRoot, file).replaceAll('\\', '/');
  const bytes = fs.readFileSync(file);
  treeHash.update(relativePath);
  treeHash.update('\0');
  treeHash.update(bytes);
  treeHash.update('\0');
  return {
    path: relativePath,
    bytes: bytes.length,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  };
});

const indexHtml = fs.readFileSync(path.join(distRoot, 'index.html'), 'utf8');
assert.match(indexHtml, new RegExp(`/assets/index-[^"']+-${manifest.assetNamespace}\\.js`), 'index entry does not use the release asset namespace');
for (const assetPath of [...indexHtml.matchAll(/(?:src|href)="(\/assets\/[^"?#]+)"/g)].map((match) => match[1])) {
  assert.ok(fs.existsSync(path.join(distRoot, assetPath.slice(1))), `index references missing asset ${assetPath}`);
}

const identity = {
  schemaVersion: 1,
  releaseId: manifest.releaseId,
  frontendVersion: manifest.frontendVersion,
  migrationHead: manifest.migrationHead,
  migrationSha256: manifest.migrationSha256,
  frontendSourceSha256: manifest.frontendSourceSha256,
  frontendBuildConfigSha256: manifest.frontendBuildConfigSha256,
  gatewayVersion: manifest.gatewayVersion,
  distFileCount: files.length,
  distTreeSha256: treeHash.digest('hex'),
  files,
};
const identityPath = path.join(identityRoot, `${manifest.releaseId}.dist-identity.json`);

if (writeMode) {
  fs.mkdirSync(identityRoot, { recursive: true });
  if (fs.existsSync(identityPath)) {
    assert.deepEqual(readJson(identityPath, 'existing release identity'), identity, 'an existing release identity cannot be overwritten with different bytes');
    console.log(`Release artifact already sealed: ${identityPath}`);
  } else {
    fs.writeFileSync(identityPath, `${JSON.stringify(identity, null, 2)}\n`, 'utf8');
    console.log(`Release artifact sealed outside dist: ${identityPath}`);
  }
} else {
  assert.deepEqual(readJson(identityPath, 'sealed release identity'), identity, 'dist no longer matches its sealed release identity');
  console.log(`Release artifact verification PASS: ${identityPath}`);
}

console.log(`Release ID: ${identity.releaseId}`);
console.log(`dist files: ${identity.distFileCount}; dist tree SHA-256: ${identity.distTreeSha256}`);
