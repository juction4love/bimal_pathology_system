import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const distRoot = path.join(root, 'dist');
const sealer = path.join(root, 'scripts/seal-release-artifact.js');

// This is a read-only prerequisite. It rejects an unsealed or changed dist and
// never writes a release identity in --verify mode.
execFileSync(process.execPath, [sealer, '--verify'], { cwd: root, stdio: 'inherit' });

const manifest = JSON.parse(fs.readFileSync(path.join(distRoot, 'release-manifest.json'), 'utf8'));
const indexHtml = fs.readFileSync(path.join(distRoot, 'index.html'), 'utf8');
assert.equal(manifest.schemaVersion, 2, 'release manifest schema must be version 2');
assert.match(indexHtml, new RegExp(`/assets/index-[^"']+-${manifest.assetNamespace}\\.js`), 'index entry namespace does not match the release manifest');

function filesUnder(directory) {
  return fs.readdirSync(directory, { withFileTypes: true })
    .flatMap((entry) => entry.isDirectory()
      ? filesUnder(path.join(directory, entry.name))
      : [path.join(directory, entry.name)]);
}

const mimeTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.webmanifest', 'application/manifest+json; charset=utf-8'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);

const server = http.createServer((request, response) => {
  try {
    const requestUrl = new URL(request.url ?? '/', 'http://127.0.0.1');
    const pathname = decodeURIComponent(requestUrl.pathname);
    const relativePath = pathname === '/' || pathname === '/login' ? 'index.html' : pathname.replace(/^\/+/, '');
    const target = path.resolve(distRoot, relativePath);
    const relativeTarget = path.relative(distRoot, target);
    if (relativeTarget.startsWith('..') || path.isAbsolute(relativeTarget)) {
      response.writeHead(403).end();
      return;
    }
    if (!fs.existsSync(target) || !fs.statSync(target).isFile()) {
      response.writeHead(404).end();
      return;
    }
    const bytes = fs.readFileSync(target);
    response.writeHead(200, {
      'Content-Type': mimeTypes.get(path.extname(target).toLowerCase()) ?? 'application/octet-stream',
      'Content-Length': bytes.length,
      'Cache-Control': 'no-store',
    });
    response.end(bytes);
  } catch {
    response.writeHead(400).end();
  }
});

await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});
const address = server.address();
assert.ok(address && typeof address === 'object', 'loopback preview server did not bind');
const baseUrl = `http://127.0.0.1:${address.port}`;

let browser;
try {
  const assetFiles = filesUnder(path.join(distRoot, 'assets')).sort((a, b) => a.localeCompare(b));
  for (const assetFile of assetFiles) {
    const relativePath = path.relative(distRoot, assetFile).replaceAll('\\', '/');
    const expectedBytes = fs.readFileSync(assetFile);
    const response = await fetch(`${baseUrl}/${relativePath}`, { redirect: 'error' });
    assert.equal(response.status, 200, `${relativePath} did not return HTTP 200`);
    const actualBytes = Buffer.from(await response.arrayBuffer());
    assert.equal(actualBytes.length, expectedBytes.length, `${relativePath} response length changed`);
    assert.equal(
      crypto.createHash('sha256').update(actualBytes).digest('hex'),
      crypto.createHash('sha256').update(expectedBytes).digest('hex'),
      `${relativePath} response bytes changed`,
    );
  }

  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ serviceWorkers: 'block' });
  const blockedExternalRequests = [];
  const localFailures = [];
  const pageErrors = [];
  const supabaseResponses = [];

  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.origin !== baseUrl) {
      blockedExternalRequests.push(route.request().url());
      await route.abort('blockedbyclient');
      return;
    }
    await route.continue();
  });

  const page = await context.newPage();
  page.on('pageerror', (error) => pageErrors.push(error.message));
  page.on('requestfailed', (request) => {
    if (request.url().startsWith(baseUrl)) localFailures.push(`${request.method()} ${request.url()}`);
  });
  page.on('response', (response) => {
    if (/\.supabase\.co(?:\/|$)/i.test(response.url())) supabaseResponses.push(response.url());
    if (response.url().startsWith(baseUrl) && response.status() >= 400) {
      localFailures.push(`${response.status()} ${response.url()}`);
    }
  });

  const documentResponse = await page.goto(`${baseUrl}/login`, { waitUntil: 'domcontentloaded' });
  assert.equal(documentResponse?.status(), 200, 'login shell document did not return HTTP 200');
  await page.locator('#login-email').waitFor({ state: 'visible', timeout: 20_000 });
  await page.locator('#login-password').waitFor({ state: 'visible', timeout: 20_000 });
  await page.locator('#login-submit').waitFor({ state: 'visible', timeout: 20_000 });
  assert.deepEqual(localFailures, [], 'login shell had failed local requests');
  assert.deepEqual(pageErrors, [], 'login shell raised JavaScript page errors');
  assert.deepEqual(supabaseResponses, [], 'the preview browser received a Supabase response');

  await context.close();
  console.log(`Immutable preview verification PASS: ${manifest.releaseId}`);
  console.log(`Assets served and byte-verified: ${assetFiles.length}`);
  console.log(`External requests blocked before dispatch: ${blockedExternalRequests.length}; Supabase responses: 0`);
} finally {
  if (browser) await browser.close();
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}
