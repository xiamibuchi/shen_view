const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { readSourceDelivery, verifySourceLinks } = require('./source-delivery.cjs');
const { sourceFixture } = require('./release-test-fixture.cjs');

test('source publication binds complete assets to the package, commit and lock across line endings', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-sources-'));
  fs.mkdirSync(path.join(root, 'release-artifact'));
  const manifest = { package: 'portable.zip', sourceCommit: 'c'.repeat(40), windowsVersion: '0.1.0.1' };
  fs.writeFileSync(path.join(root, 'release-artifact', manifest.package), 'portable bytes');
  const fixture = sourceFixture(root, manifest);
  const read = () => readSourceDelivery(path.join(root, 'release-artifact'), manifest, fixture.lockPath);
  try {
    assert.equal(read().uploads.length, 3);
    const originalUrl = fixture.delivery.source.url;
    fixture.delivery.source.url = 'https://github.com/xiamibuchi/shen_view/tree/main'; fixture.write();
    assert.throws(read, /exact merged commit/);
    fixture.delivery.source.url = originalUrl;
    const remote = fixture.delivery.assets[0];
    const originalLocation = remote.location;
    remote.location = 'local'; fixture.write();
    assert.throws(read, /stale/);
    remote.location = originalLocation;
    const originalRemoteUrl = remote.url;
    remote.url = 'https://github.com/example/upstream'; fixture.write();
    assert.throws(read, /stale/);
    remote.url = originalRemoteUrl; fixture.write();
    fs.writeFileSync(fixture.lockPath, fs.readFileSync(fixture.lockPath, 'utf8').replaceAll('\n', '\r\n'));
    assert.equal(read().uploads.length, 3);
    const originalCommit = fixture.delivery.sourceCommit;
    fixture.delivery.sourceCommit = 'another-commit'; fixture.write();
    assert.throws(read, /match/);
    fixture.delivery.sourceCommit = originalCommit;
    fixture.delivery.sourceDirty = true; fixture.write();
    assert.throws(read, /match/);
    fixture.delivery.sourceDirty = false;
    const last = fixture.delivery.assets.pop(); fixture.write();
    assert.throws(read, /Incomplete/);
    fixture.delivery.assets.push(last); fixture.write();
    const first = fixture.delivery.assets.find(asset => asset.location === 'local');
    const name = first.name;
    first.name = '../outside.zip';
    fs.writeFileSync(path.join(fixture.sourceDirectory, 'SOURCES.json'), JSON.stringify(fixture.delivery));
    assert.throws(read, /Unexpected/);
    first.name = name; fixture.write();
    fs.appendFileSync(path.join(fixture.sourceDirectory, name), 'tampered');
    assert.throws(read, /checksum or size/);
  } finally { fs.rmSync(root, { recursive: true }); }
});

test('remote source checks reject unavailable, unpublished, replaced or damaged archives', async () => {
  const digest = 'd'.repeat(64);
  const delivery = { sourceCommit: 'c'.repeat(40), assets: [{ id: 'hdr-sdk', location: 'remote',
    name: 'source.zip', url: 'https://github.com/xiamibuchi/shen_view/releases/download/native-sdk-v1.0.1/source.zip',
    bytes: 10, sha256: digest }] };
  let draft = false;
  let remote = { name: 'source.zip', size: 10, state: 'uploaded', digest: 'sha256:' + digest };
  const github = { paginate: async () => remote ? [remote] : [], rest: {
    git: { getCommit: async () => ({ data: { sha: delivery.sourceCommit } }) },
    repos: { getReleaseByTag: async args => ({ data: { id: 1, tag_name: args.tag, draft } }), listReleaseAssets() {} },
  } };
  await verifySourceLinks(github, delivery);
  draft = true;
  await assert.rejects(verifySourceLinks(github, delivery), /publicly/);
  draft = false;
  remote.digest = 'sha256:' + 'e'.repeat(64);
  await assert.rejects(verifySourceLinks(github, delivery), /changed/);
  remote.digest = 'sha256:' + digest;
  remote.size = 11;
  await assert.rejects(verifySourceLinks(github, delivery), /damaged/);
  remote = null;
  await assert.rejects(verifySourceLinks(github, delivery), /missing/);
});

test('missing source delivery blocks publication and receipts cannot authorize a different binary', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-source-missing-'));
  const manifest = { package: 'portable.zip', sourceCommit: 'c'.repeat(40), windowsVersion: '0.1.0.1' };
  fs.mkdirSync(path.join(root, 'release-artifact'));
  fs.writeFileSync(path.join(root, 'release-artifact', manifest.package), 'portable bytes');
  try {
    assert.throws(() => readSourceDelivery(path.join(root, 'release-artifact'), manifest), /exactly one/);
    const fixture = sourceFixture(root, manifest);
    const read = () => readSourceDelivery(path.join(root, 'release-artifact'), manifest, fixture.lockPath);
    fixture.delivery.assets[0].binarySha256 = 'b'.repeat(64); fixture.write();
    assert.throws(read, /stale/);
    fixture.delivery.assets[0].binarySha256 = 'a'.repeat(64); fixture.write();
    fs.appendFileSync(path.join(root, 'release-artifact', manifest.package), 'another build');
    assert.throws(read, /another portable/);
  } finally { fs.rmSync(root, { recursive: true }); }
});
