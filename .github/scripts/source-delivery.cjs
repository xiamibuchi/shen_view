const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function hashFile(file) {
  const hash = crypto.createHash('sha256');
  const buffer = Buffer.alloc(1024 * 1024);
  const fd = fs.openSync(file, 'r');
  try {
    let size;
    while ((size = fs.readSync(fd, buffer, 0, buffer.length, null)) > 0) hash.update(buffer.subarray(0, size));
    return hash.digest('hex');
  } finally { fs.closeSync(fd); }
}

function readSourceDelivery(root, manifest, lockPath = 'third_party/release-sources.lock.json') {
  const entries = fs.readdirSync(root, { recursive: true }).filter(name => path.basename(name) === 'SOURCES.json');
  if (entries.length !== 1) throw new Error('Expected exactly one source-delivery manifest');
  const directory = path.dirname(path.join(root, entries[0]));
  const delivery = JSON.parse(fs.readFileSync(path.join(directory, 'SOURCES.json'), 'utf8'));
  const lockText = fs.readFileSync(lockPath, 'utf8').replaceAll('\r\n', '\n');
  const lock = JSON.parse(lockText);
  if (lock.schema !== 1 || delivery.schema !== 1 || delivery.sourceDirty !== false ||
      delivery.sourceCommit !== manifest.sourceCommit || delivery.package !== manifest.package ||
      delivery.sourceLockSha256 !== crypto.createHash('sha256').update(lockText).digest('hex')) {
    throw new Error('Source delivery does not match the merged package and source lock');
  }
  const packages = fs.readdirSync(root, { recursive: true }).filter(name => path.basename(name) === manifest.package);
  if (packages.length !== 1 || hashFile(path.join(root, packages[0])) !== delivery.packageSha256) {
    throw new Error('Source delivery is for another portable package');
  }
  const expected = new Map(lock.assets.map(asset => [asset.id, asset]));
  expected.set('shenview', { name: 'ShenView-' + manifest.windowsVersion + '-source.zip' });
  expected.set('notices', { name: 'ShenView-' + manifest.windowsVersion + '-notices.zip' });
  if (!Array.isArray(delivery.assets) || delivery.assets.length !== expected.size) throw new Error('Incomplete source delivery');
  const assets = [];
  for (const asset of delivery.assets) {
    const entry = expected.get(asset.id);
    if (!entry || asset.name !== (entry.name || new URL(entry.url).pathname.split('/').pop()) ||
        path.basename(asset.name) !== asset.name || asset.name.includes('\\') ||
        (entry.sha256 && (entry.sha256 !== asset.sha256 || entry.url !== asset.url || entry.binarySha256 !== asset.binarySha256))) {
      throw new Error('Unexpected or stale source asset');
    }
    const file = path.join(directory, asset.name);
    if (fs.lstatSync(file).isSymbolicLink() || fs.statSync(file).size !== asset.bytes || hashFile(file) !== asset.sha256) {
      throw new Error('Source asset checksum or size mismatch: ' + asset.name);
    }
    expected.delete(asset.id);
    assets.push({ name: asset.name, file });
  }
  for (const name of ['SOURCES.json', 'SOURCES.md']) assets.push({ name, file: path.join(directory, name) });
  const checksums = fs.readFileSync(path.join(directory, 'SOURCES-SHA256SUMS.txt'), 'utf8').trim().split(/\r?\n/);
  const actual = assets.map(asset => hashFile(asset.file) + '  ' + asset.name);
  if (checksums.length !== actual.length || new Set(checksums).size !== actual.length || actual.some(line => !checksums.includes(line))) {
    throw new Error('Source-delivery checksums do not match the assets');
  }
  assets.push({ name: 'SOURCES-SHA256SUMS.txt', file: path.join(directory, 'SOURCES-SHA256SUMS.txt') });
  return assets;
}

module.exports = { hashFile, readSourceDelivery };
