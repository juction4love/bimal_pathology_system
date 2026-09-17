import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const node = process.execPath;

function filesUnder(directory) {
  return fs.readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => entry.isDirectory()
      ? filesUnder(path.join(directory, entry.name))
      : [path.join(directory, entry.name)]);
}

function snapshot() {
  const dist = path.join(root, 'dist');
  const manifestBytes = fs.readFileSync(path.join(dist, 'release-manifest.json'));
  const manifest = JSON.parse(manifestBytes);
  const tree = crypto.createHash('sha256');
  const files = filesUnder(dist).sort((a, b) => a.localeCompare(b)).map((file) => {
    const relative = path.relative(dist, file).replaceAll('\\', '/');
    const bytes = fs.readFileSync(file);
    tree.update(relative);
    tree.update('\0');
    tree.update(bytes);
    tree.update('\0');
    return { path: relative, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
  });
  return {
    releaseId: manifest.releaseId,
    manifestSha256: crypto.createHash('sha256').update(manifestBytes).digest('hex'),
    distTreeSha256: tree.digest('hex'),
    files,
  };
}

function build() {
  if (process.platform === 'win32') {
    execFileSync(process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', ['/d', '/s', '/c', 'npm run build'], { cwd: root, stdio: 'inherit' });
  } else {
    execFileSync('npm', ['run', 'build'], { cwd: root, stdio: 'inherit' });
  }
  return snapshot();
}

const first = build();
const second = build();
assert.deepEqual(second, first, 'two clean builds from identical inputs must be byte-identical');
execFileSync(node, ['scripts/seal-release-artifact.js', '--verify'], { cwd: root, stdio: 'inherit' });
console.log(JSON.stringify({ pass: true, ...first }, null, 2));
