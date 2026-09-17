import fs from 'node:fs';

let passed = 0;
let failed = 0;
function check(condition, name, detail) {
  if (condition) {
    passed += 1;
    console.log(`PASS ${name}: ${detail}`);
  } else {
    failed += 1;
    console.error(`FAIL ${name}: ${detail}`);
  }
}

const manifest = JSON.parse(fs.readFileSync('public/manifest.webmanifest', 'utf8'));
const worker = fs.readFileSync('public/service-worker.js', 'utf8');
const main = fs.readFileSync('src/main.tsx', 'utf8');
const layout = fs.readFileSync('src/app/AppLayout.tsx', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

check(manifest.name === 'Bimal Pathology LIS' && manifest.short_name === 'Bimal LIS', 'Identity', 'manifest has the required app names');
check(manifest.start_url === 'https://lis.bimalpathology.com.np/' && manifest.scope === 'https://lis.bimalpathology.com.np/', 'ProductionScope', 'manifest opens the production LIS origin');
check(manifest.display === 'standalone', 'Standalone', 'manifest requests standalone display mode');
check(manifest.theme_color === '#0b6b3a' && manifest.background_color === '#f2f7f4', 'ClinicalTheme', 'manifest matches the green clinical theme');
check(manifest.icons.some((icon) => icon.sizes === '192x192') && manifest.icons.some((icon) => icon.sizes === '512x512'), 'InstallIcons', 'manifest includes required install icon sizes');
check(manifest.icons.every((icon) => fs.existsSync(`public${icon.src}`)), 'IconFiles', 'every manifest icon exists');
check(html.includes('rel="manifest" href="/manifest.webmanifest"') && html.includes('name="theme-color" content="#0b6b3a"'), 'DocumentMetadata', 'HTML links the manifest and theme color');
check(main.includes("navigator.serviceWorker.register('/service-worker.js', { scope: '/' })") && main.includes('import.meta.env.PROD'), 'WorkerRegistration', 'service worker registers only in production builds');
check(!/caches\s*\.|CacheStorage|respondWith\s*\(|addEventListener\s*\(\s*['"]fetch/i.test(worker), 'NoClinicalCaching', 'worker has no Cache API or fetch interception');
check(layout.includes("window.addEventListener('beforeinstallprompt'") && layout.includes('Install App'), 'InstallAction', 'supported browsers expose an Install App action');

console.log(`\nPWA verification: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
