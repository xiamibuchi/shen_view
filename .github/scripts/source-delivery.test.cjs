const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { readSourceDelivery } = require('./source-delivery.cjs');
const { sourceFixture } = require('./release-test-fixture.cjs');

test('source publication binds complete assets to the package, commit and lock across line endings', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-sources-'));
  fs.mkdirSync(path.join(root, 'release-artifact'));
  const manifest = { package: 'portable.zip', sourceCommit: 'merged', windowsVersion: '0.1.0.1' };
  fs.writeFileSync(path.join(root, 'release-artifact', manifest.package), 'portable bytes');
  const fixture = sourceFixture(root, manifest);
  const read = () => readSourceDelivery(path.join(root, 'release-artifact'), manifest, fixture.lockPath);
  try {
    assert.equal(read().length, 9);
    fs.writeFileSync(fixture.lockPath, fs.readFileSync(fixture.lockPath, 'utf8').replaceAll('\n', '\r\n'));
    assert.equal(read().length, 9);
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
    const first = fixture.delivery.assets[0];
    const name = first.name;
    first.name = '../outside.zip';
    fs.writeFileSync(path.join(fixture.sourceDirectory, 'SOURCES.json'), JSON.stringify(fixture.delivery));
    assert.throws(read, /Unexpected/);
    first.name = name; fixture.write();
    fs.appendFileSync(path.join(fixture.sourceDirectory, name), 'tampered');
    assert.throws(read, /checksum or size/);
  } finally { fs.rmSync(root, { recursive: true }); }
});

test('missing source delivery blocks publication and receipts cannot authorize a different binary', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-source-missing-'));
  const manifest = { package: 'portable.zip', sourceCommit: 'merged', windowsVersion: '0.1.0.1' };
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
