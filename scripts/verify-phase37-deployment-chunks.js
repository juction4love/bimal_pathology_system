/** Cache, atomic deployment, lazy-route, and chunk-recovery regression suite. */
import fs from 'node:fs';
import path from 'node:path';

const read = (file) => fs.readFileSync(file, 'utf8');
const lazyPages = read('src/app/lazyPages.ts');
const recovery = read('src/app/lazyWithChunkRecovery.ts');
const routeBoundary = read('src/components/common/RouteErrorBoundary.tsx');
const routes = read('src/app/routes.tsx');
const layout = read('src/app/AppLayout.tsx');
const headers = read('public/_headers');
const deployment = read('DEPLOY_CLOUDFLARE.md');
const redirects = read('public/_redirects');
const packageJson = JSON.parse(read('package.json'));
const viteConfig = read('vite.config.ts');
const releaseGenerator = read('scripts/generate-release-manifest.js');
const artifactSealer = read('scripts/seal-release-artifact.js');
const previewVerifier = read('scripts/verify-release-preview.js');
let passed = 0;
const check = (condition, message) => { if (!condition) throw new Error(message); passed++; console.log(`PASS ${message}`); };

const imports = [...lazyPages.matchAll(/lazyWithChunkRecovery\('([^']+)', \(\) => import\('([^']+)'\)/g)];
check(imports.length === 23, 'all 23 lazy page modules use the recovery loader');
check(new Set(imports.map((match) => match[1])).size === imports.length, 'every lazy route has a unique reload-loop key');
check(imports.some((match) => match[1] === 'WorklistPage' && match[2] === '@/features/worklist/WorklistPage'), 'Worklist uses bounded chunk recovery');
check(/Failed to fetch dynamically imported module/.test(recovery) && /Importing a module script failed/.test(recovery) && /ChunkLoadError/.test(recovery), 'known browser chunk-load failures are recognized');
check(recovery.includes("sessionStorage.getItem(key) !== 'attempted'") && recovery.includes("sessionStorage.setItem(key, 'attempted')"), 'automatic refresh is limited to one attempt per route and path');
check(recovery.includes('window.location.reload()') && recovery.includes('return new Promise<never>'), 'first chunk mismatch reloads once without rendering a stale failure');
check(routeBoundary.includes('New version available — Refresh') && routeBoundary.includes('clearChunkReloadMarkers()'), 'repeated mismatch offers an explicit manual refresh');
check(routes.includes('<RouteErrorBoundary>') && layout.includes('<RouteErrorBoundary>'), 'public and authenticated lazy routes have route error boundaries');
check(/\/index\.html[\s\S]*Cache-Control: no-cache, no-store, must-revalidate/.test(headers), 'index.html is never retained stale');
check(/\/assets\/\*[\s\S]*Cache-Control: public, max-age=31536000, immutable/.test(headers), 'hashed assets use immutable long caching');
check(/\/service-worker\.js[\s\S]*Cache-Control: no-cache, no-store, must-revalidate/.test(headers), 'service worker is never retained stale');
check(/\/release-manifest\.json[\s\S]*Cache-Control: no-cache, no-store, must-revalidate/.test(headers), 'release manifest is never retained stale');
check(packageJson.version === '1.0.0' && viteConfig.includes('assetNamespace') && !viteConfig.includes('r20260824a'), 'frontend version owns the Vite JavaScript asset namespace');
check(releaseGenerator.includes('schemaVersion: 2') && releaseGenerator.includes('frontendBuildConfigSha256') && releaseGenerator.includes('Duplicate migration version(s)'), 'release manifest validates target configuration and migration identity');
check(artifactSealer.includes('distTreeSha256') && artifactSealer.includes('artifacts/releases') && !artifactSealer.includes('writeFileSync(dist'), 'release sealer records identity outside dist without mutating the built artifact');
check(previewVerifier.includes("route('**/*'") && previewVerifier.includes("route.abort('blockedbyclient')") && previewVerifier.includes("execFileSync(process.execPath, [sealer, '--verify']"), 'immutable preview verifier seals first and blocks every external browser request');
check(previewVerifier.includes("page.goto(`${baseUrl}/login`") && previewVerifier.includes("locator('#login-submit')") && previewVerifier.includes('supabaseResponses'), 'immutable preview verifier renders the login shell without accepting a Supabase response');
check(deployment.includes('one indivisible deployment artifact') && deployment.includes('Never copy `index.html`') && deployment.includes('preview URL'), 'deployment guide requires whole-dist atomic preview promotion');
check(!/^\/\* \/(?:index\.html)? 200$/m.test(redirects) && redirects.includes('/worklist / 200') && redirects.includes('/r/* / 200'), 'SPA rewrites are allowlisted and never rewrite missing assets to index HTML');
check(fs.existsSync('public/404.html'), 'a top-level 404 document disables implicit Pages SPA fallback for unknown assets');

if (fs.existsSync('dist/index.html')) {
  check(fs.existsSync('dist/_headers'), 'production build includes Cloudflare cache headers');
  const builtFiles = new Set(fs.readdirSync('dist/assets'));
  const assetReferences = [];
  for (const file of builtFiles) {
    if (!file.endsWith('.js')) continue;
    const source = read(path.join('dist/assets', file));
    for (const match of source.matchAll(/["']\.\/([^"']+\.js)["']/g)) assetReferences.push(match[1]);
  }
  check(assetReferences.every((file) => builtFiles.has(file)), 'every built dynamic-import chunk reference resolves inside the same dist artifact');
}

console.log(`Deployment chunk regression: ${passed} passed, 0 failed`);
