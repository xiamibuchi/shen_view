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
  if (lock.schema !== 2 || delivery.schema !== 2 || delivery.sourceDirty !== false ||
      delivery.sourceCommit !== manifest.sourceCommit || delivery.package !== manifest.package ||
      delivery.sourceLockSha256 !== crypto.createHash('sha256').update(lockText).digest('hex')) {
    throw new Error('Source delivery does not match the merged package and source lock');
  }
  const packages = fs.readdirSync(root, { recursive: true }).filter(name => path.basename(name) === manifest.package);
  if (packages.length !== 1 || hashFile(path.join(root, packages[0])) !== delivery.packageSha256) {
    throw new Error('Source delivery is for another portable package');
  }
  const expected = new Map(lock.assets.map(asset => [asset.id, asset]));
  const repository = 'https://github.com/xiamibuchi/shen_view';
  const source = delivery.source;
  if (!/^[a-f0-9]{40}$/.test(manifest.sourceCommit) || source?.commit !== manifest.sourceCommit ||
      source.url !== repository + '/tree/' + manifest.sourceCommit ||
      source.archiveUrl !== repository + '/archive/' + manifest.sourceCommit + '.zip' ||
      source.instructionsUrl !== repository + '/blob/' + manifest.sourceCommit + '/docs/release/source-delivery.md') {
    throw new Error('Source links must name the exact merged commit');
  }
  expected.set('notices', { name: 'ShenView-' + manifest.windowsVersion + '-notices.zip', location: 'local' });
  if (!Array.isArray(delivery.assets) || delivery.assets.length !== expected.size) throw new Error('Incomplete source delivery');
  const uploads = [];
  for (const asset of delivery.assets) {
    const entry = expected.get(asset.id);
    const location = entry?.location || 'remote';
    if (!entry || asset.name !== (entry.name || new URL(entry.url).pathname.split('/').pop()) ||
        path.basename(asset.name) !== asset.name || asset.name.includes('\\') ||
        asset.location !== location || !Number.isSafeInteger(asset.bytes) || asset.bytes <= 0 ||
        !/^[a-f0-9]{64}$/.test(asset.sha256) ||
        (entry.sha256 && (entry.sha256 !== asset.sha256 || entry.url !== asset.url ||
          entry.bytes !== asset.bytes || entry.binarySha256 !== asset.binarySha256 ||
          !/^https:\/\/github\.com\/xiamibuchi\/shen_view\/releases\/download\/(native-sdk-v[0-9]+\.[0-9]+\.[0-9]+|third-party-sources-v[1-9][0-9]*)\/[A-Za-z0-9_.-]+$/.test(asset.url)))) {
      throw new Error('Unexpected or stale source asset');
    }
    expected.delete(asset.id);
    if (location === 'remote') continue;
    const file = path.join(directory, asset.name);
    if (fs.lstatSync(file).isSymbolicLink() || fs.statSync(file).size !== asset.bytes || hashFile(file) !== asset.sha256) {
      throw new Error('Source asset checksum or size mismatch: ' + asset.name);
    }
    uploads.push({ name: asset.name, file });
  }
  if (expected.size) throw new Error('Incomplete or duplicate source delivery');
  uploads.push({ name: 'SOURCES.json', file: path.join(directory, 'SOURCES.json') });
  const checksums = fs.readFileSync(path.join(directory, 'SOURCES-SHA256SUMS.txt'), 'utf8').trim().split(/\r?\n/);
  const actual = uploads.map(asset => hashFile(asset.file) + '  ' + asset.name);
  if (checksums.length !== actual.length || new Set(checksums).size !== actual.length || actual.some(line => !checksums.includes(line))) {
    throw new Error('Source-delivery checksums do not match the assets');
  }
  uploads.push({ name: 'SOURCES-SHA256SUMS.txt', file: path.join(directory, 'SOURCES-SHA256SUMS.txt') });
  return { uploads, delivery };
}

async function verifySourceLinks(github, delivery) {
  const repo = { owner: 'xiamibuchi', repo: 'shen_view' };
  const commit = await github.rest.git.getCommit({ ...repo, commit_sha: delivery.sourceCommit });
  if (commit.data.sha !== delivery.sourceCommit) throw new Error('Source commit is unavailable');
  const releases = new Map();
  for (const asset of delivery.assets.filter(asset => asset.location === 'remote')) {
    const tag = new URL(asset.url).pathname.split('/')[5];
    if (!releases.has(tag)) {
      const release = (await github.rest.repos.getReleaseByTag({ ...repo, tag })).data;
      if (release.draft || release.tag_name !== tag) throw new Error('Source release must be publicly downloadable');
      releases.set(tag, await github.paginate(github.rest.repos.listReleaseAssets, { ...repo, release_id: release.id, per_page: 100 }));
    }
    const remote = releases.get(tag).find(item => item.name === asset.name);
    if (!remote || remote.state !== 'uploaded' || remote.size !== asset.bytes || remote.digest !== 'sha256:' + asset.sha256) {
      throw new Error('Source link is missing, damaged or changed: ' + asset.id);
    }
  }
}

module.exports = { hashFile, readSourceDelivery, verifySourceLinks };
