import assert from 'node:assert/strict';
import test from 'node:test';

class ArtifactStore {
  constructor() { this.metadata = new Map(); this.objects = new Map(); }
  queue(reportId, version, snapshotHash) {
    const identity = `${reportId}:v${version}`;
    if (!this.metadata.has(identity)) this.metadata.set(identity, { reportId, version, snapshotHash, status: 'Pending' });
    return this.metadata.get(identity);
  }
  upload(identity, key, bytes, hash, fail = false) {
    const artifact = this.metadata.get(identity);
    if (!artifact || artifact.status === 'Ready') throw new Error('IMMUTABLE_ARTIFACT');
    if (fail) { artifact.status = 'UploadFailed'; return; }
    const existing = this.objects.get(key);
    if (existing && existing.hash !== hash) throw new Error('R2_OBJECT_HASH_CONFLICT');
    if (!existing) this.objects.set(key, { bytes, hash });
    artifact.status = 'Ready'; artifact.key = key; artifact.hash = hash; artifact.size = bytes.length;
  }
  authorize(identity, token, now = 10) {
    const artifact = this.metadata.get(identity);
    return Boolean(token?.active && !token.revoked && token.expires > now && artifact?.status === 'Ready');
  }
  read(identity, token, unavailable = false) {
    if (!this.authorize(identity, token) || unavailable) return { status: unavailable ? 503 : 404 };
    const artifact = this.metadata.get(identity); const object = this.objects.get(artifact.key);
    if (!object || object.hash !== artifact.hash || object.bytes.length !== artifact.size) return { status: 503 };
    return { status: 200, headers: { 'cache-control': 'private, no-store, max-age=0', 'content-type': 'application/pdf' } };
  }
}

const id = '00000000-0000-4000-8000-000000000001';
const hash = 'a'.repeat(64);
const key = version => `reports/2026/${id}/v${version}/${hash}.pdf`;

test('duplicate queue and upload produce one immutable artifact', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.queue(id, 1, hash);
  assert.equal(s.metadata.size, 1); s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash);
  assert.throws(() => s.upload(`${id}:v1`, key(1), new Uint8Array([2]), hash), /IMMUTABLE_ARTIFACT/);
});

test('upload failure never publishes Ready and can retry safely', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash, true);
  assert.equal(s.metadata.get(`${id}:v1`).status, 'UploadFailed');
  assert.equal(s.authorize(`${id}:v1`, { active: true, revoked: false, expires: 20 }), false);
  s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash); assert.equal(s.metadata.get(`${id}:v1`).status, 'Ready');
});

test('read failure and hash mismatch fail closed', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash);
  const token = { active: true, revoked: false, expires: 20 };
  assert.equal(s.read(`${id}:v1`, token, true).status, 503);
  s.objects.get(key(1)).hash = 'b'.repeat(64); assert.equal(s.read(`${id}:v1`, token).status, 503);
});

test('expired, revoked, inactive, and missing tokens cannot read', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash);
  for (const token of [null, { active: false, expires: 20 }, { active: true, revoked: true, expires: 20 }, { active: true, revoked: false, expires: 10 }])
    assert.equal(s.read(`${id}:v1`, token).status, 404);
});

test('amendments are isolated by report version and object key', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.queue(id, 2, 'b'.repeat(64));
  s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash); s.upload(`${id}:v2`, key(2), new Uint8Array([2]), hash);
  assert.notEqual(s.metadata.get(`${id}:v1`).key, s.metadata.get(`${id}:v2`).key);
});

test('authorized response is PDF and never publicly cacheable', () => {
  const s = new ArtifactStore(); s.queue(id, 1, hash); s.upload(`${id}:v1`, key(1), new Uint8Array([1]), hash);
  const result = s.read(`${id}:v1`, { active: true, revoked: false, expires: 20 });
  assert.equal(result.status, 200); assert.equal(result.headers['content-type'], 'application/pdf');
  assert.match(result.headers['cache-control'], /private/); assert.match(result.headers['cache-control'], /no-store/);
});
