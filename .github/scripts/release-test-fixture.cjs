const fs = require('node:fs');
const path = require('node:path');
const { hashFile } = require('./source-delivery.cjs');

function sourceFixture(root, manifest) {
  const sourceDirectory = path.join(root, 'release-artifact', 'sources');
  fs.mkdirSync(sourceDirectory, { recursive: true });
  fs.mkdirSync(path.join(root, 'third_party'), { recursive: true });
  const records = [];
  const lock = { schema: 1, assets: [] };
  for (const id of ['imagemagick-windows', '7zip', 'hdr-sdk', 'ffmpeg-sdk', 'shenview', 'notices']) {
    const name = id === 'shenview' ? 'ShenView-' + manifest.windowsVersion + '-source.zip' :
      id === 'notices' ? 'ShenView-' + manifest.windowsVersion + '-notices.zip' : id + '.zip';
    const file = path.join(sourceDirectory, name);
    fs.writeFileSync(file, 'test source bytes: ' + id);
    const asset = { id, name, bytes: fs.statSync(file).size, sha256: hashFile(file),
      url: 'https://github.com/example/project/releases/download/1.0/' + name, binarySha256: 'a'.repeat(64) };
    records.push(asset);
    if (id !== 'shenview' && id !== 'notices') lock.assets.push(asset);
  }
  const lockPath = path.join(root, 'third_party', 'release-sources.lock.json');
  fs.writeFileSync(lockPath, JSON.stringify(lock) + '\n');
  const delivery = { schema: 1, sourceCommit: manifest.sourceCommit, sourceDirty: false,
    package: manifest.package, packageSha256: hashFile(path.join(root, 'release-artifact', manifest.package)),
    sourceLockSha256: hashFile(lockPath), assets: records };
  const write = () => {
    fs.writeFileSync(path.join(sourceDirectory, 'SOURCES.json'), JSON.stringify(delivery));
    fs.writeFileSync(path.join(sourceDirectory, 'SOURCES.md'), 'Unsigned test source delivery');
    const names = records.map(asset => asset.name).concat(['SOURCES.json', 'SOURCES.md']);
    fs.writeFileSync(path.join(sourceDirectory, 'SOURCES-SHA256SUMS.txt'),
      names.map(name => hashFile(path.join(sourceDirectory, name)) + '  ' + name).join('\n') + '\n');
  };
  write();
  return { delivery, lockPath, sourceDirectory, write };
}

module.exports = { sourceFixture };
