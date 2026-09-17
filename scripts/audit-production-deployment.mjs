import crypto from 'node:crypto';

const base = process.argv[2] || 'https://lis.bimalpathology.com.np';
const compareBase = process.argv[3];
const digest = (body) => crypto.createHash('sha256').update(body).digest('hex').slice(0, 16);
const paths = ['/', '/login', '/worklist', '/reports', '/catalogue', '/settings', '/index.html', '/_headers'];

for (const pathname of paths) {
  const response = await fetch(`${base}${pathname}`, { redirect: 'manual', headers: { 'cache-control': 'no-cache' } });
  const body = Buffer.from(await response.arrayBuffer());
  console.log(JSON.stringify({ pathname, status: response.status, contentType: response.headers.get('content-type'), cacheControl: response.headers.get('cache-control'), cfCacheStatus: response.headers.get('cf-cache-status'), digest: digest(body), bytes: body.length, location: response.headers.get('location') }));
}

const htmlResponse = await fetch(`${base}/?deployment-audit=${Date.now()}`, { headers: { 'cache-control': 'no-cache' } });
const html = await htmlResponse.text();
const entry = html.match(/src="(\/assets\/index-[^"]+\.js)"/)?.[1];
if (!entry) throw new Error('Production HTML has no hashed entry bundle.');
const entryResponse = await fetch(`${base}${entry}`, { headers: { 'cache-control': 'no-cache' } });
const entryBody = await entryResponse.text();
const references = [...new Set([...entryBody.matchAll(/assets\/[A-Za-z0-9_./-]+\.js/g)].map((match) => `/${match[0]}`))];
const failures = [];
const cachePolicies = new Set();
for (const pathname of references) {
  const response = await fetch(`${base}${pathname}`, { method: 'HEAD', headers: { 'cache-control': 'no-cache' } });
  const contentType = response.headers.get('content-type') || '';
  cachePolicies.add(response.headers.get('cache-control'));
  if (response.status !== 200 || !contentType.includes('javascript')) failures.push({ pathname, status: response.status, contentType, cacheControl: response.headers.get('cache-control') });
}
console.log(JSON.stringify({ entry, entryStatus: entryResponse.status, entryContentType: entryResponse.headers.get('content-type'), entryCacheControl: entryResponse.headers.get('cache-control'), entryDigest: digest(entryBody), lazyReferenceCount: references.length, cachePolicies: [...cachePolicies], failures }));

if (compareBase) {
  const mismatches = [];
  for (const pathname of [entry, ...references]) {
    const [left, right] = await Promise.all([fetch(`${base}${pathname}`), fetch(`${compareBase}${pathname}`)]);
    const [leftBody, rightBody] = await Promise.all([left.arrayBuffer(), right.arrayBuffer()]);
    const leftDigest = digest(Buffer.from(leftBody));
    const rightDigest = digest(Buffer.from(rightBody));
    if (left.status !== right.status || leftDigest !== rightDigest) mismatches.push({ pathname, leftStatus: left.status, rightStatus: right.status, leftDigest, rightDigest });
  }
  console.log(JSON.stringify({ compareBase, comparedArtifacts: references.length + 1, mismatches }));
}
