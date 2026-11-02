const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { readArtifact } = require('./release-draft.cjs');

test('release accepts only the clean merged commit and matching checksum', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-release-'));
  const manifest = {
    version: '0.1.0', windowsVersion: '0.1.0.7', sourceCommit: 'abc123', sourceDirty: false,
    installerType: 'portable', package: 'ShenView-0.1.0.7-windows-x64-portable.zip',
  };
  const write = () => fs.writeFileSync(path.join(root, 'release.json'), JSON.stringify(manifest));
  try {
    const zip = Buffer.from('portable package bytes');
    fs.writeFileSync(path.join(root, manifest.package), zip);
    fs.writeFileSync(path.join(root, 'SHA256SUMS.txt'), crypto.createHash('sha256').update(zip).digest('hex') + '  ' + manifest.package + '\n');
    write();
    assert.equal(readArtifact(root, 'abc123').tag, 'v0.1.0');
    assert.throws(() => readArtifact(root, 'another-commit'));
    manifest.sourceDirty = true; write();
    assert.throws(() => readArtifact(root, 'abc123'));
    manifest.sourceDirty = false; write();
    fs.appendFileSync(path.join(root, manifest.package), 'tampered');
    assert.throws(() => readArtifact(root, 'abc123'));
    manifest.package = '../outside.zip'; write();
    assert.throws(() => readArtifact(root, 'abc123'));
  } finally { fs.rmSync(root, { recursive: true }); }
});
