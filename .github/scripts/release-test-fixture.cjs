const fs = require('node:fs');
const path = require('node:path');
const { hashFile } = require('./source-delivery.cjs');

function sourceFixture(root, manifest) {
  const sourceDirectory = path.join(root, 'release-artifact', 'sources');
  fs.mkdirSync(sourceDirectory, { recursive: true });
  fs.mkdirSync(path.join(root, 'third_party'), { recursive: true });
  const records = [];
  const lock = { schema: 2, assets: [] };
  for (const id of ['imagemagick-windows', '7zip', 'hdr-sdk', 'ffmpeg-sdk', 'notices']) {
    const name = id === 'notices' ? 'ShenView-' + manifest.windowsVersion + '-notices.zip' : id + '.zip';
    const file = path.join(sourceDirectory, name);
    fs.writeFileSync(file, 'test source bytes: ' + id);
    const tag = id.endsWith('-sdk') ? 'native-sdk-v1.0.1' : 'third-party-sources-v1';
    const asset = { id, name, location: id === 'notices' ? 'local' : 'remote', bytes: fs.statSync(file).size, sha256: hashFile(file),
      url: 'https://github.com/xiamibuchi/shen_view/releases/download/' + tag + '/' + name, binarySha256: 'a'.repeat(64) };
    records.push(asset);
    if (id !== 'notices') { lock.assets.push(asset); fs.unlinkSync(file); }
  }
  const lockPath = path.join(root, 'third_party', 'release-sources.lock.json');
  fs.writeFileSync(lockPath, JSON.stringify(lock) + '\n');
  const repository = 'https://github.com/xiamibuchi/shen_view';
  const delivery = { schema: 2, sourceCommit: manifest.sourceCommit, sourceDirty: false,
    package: manifest.package, packageSha256: hashFile(path.join(root, 'release-artifact', manifest.package)),
    sourceLockSha256: hashFile(lockPath),
    source: {commit: manifest.sourceCommit, url: repository + '/tree/' + manifest.sourceCommit,
      archiveUrl: repository + '/archive/' + manifest.sourceCommit + '.zip',
      instructionsUrl: repository + '/blob/' + manifest.sourceCommit + '/docs/release/source-delivery.md'},
    assets: records };
  const write = () => {
    fs.writeFileSync(path.join(sourceDirectory, 'SOURCES.json'), JSON.stringify(delivery));
    const names = ['ShenView-' + manifest.windowsVersion + '-notices.zip', 'SOURCES.json'];
    fs.writeFileSync(path.join(sourceDirectory, 'SOURCES-SHA256SUMS.txt'),
      names.map(name => hashFile(path.join(sourceDirectory, name)) + '  ' + name).join('\n') + '\n');
  };
  write();
  return { delivery, lockPath, sourceDirectory, write };
}

module.exports = { sourceFixture };
