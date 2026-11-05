const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function readLock(filename = 'third_party/native-sdk.lock.json') {
  // Windows PowerShell 5.1 Set-Content -Encoding utf8 writes a BOM.
  return JSON.parse(fs.readFileSync(filename, 'utf8').replace(/^\uFEFF/, ''));
}

function readAssets(directory, lock) {
  return ['hdr', 'ffmpeg'].flatMap(component => ['sdk', 'sources'].flatMap(kind => {
    const name = kind === 'sdk' ? lock.components[component].asset : `shenview-${component}-sources-windows-x64.zip`;
    if (name !== `shenview-${component}-${kind}-windows-x64.zip`) throw new Error('Invalid SDK asset name');
    const data = fs.readFileSync(path.join(directory, name));
    const digest = crypto.createHash('sha256').update(data).digest('hex');
    const checksumName = `${component}${kind === 'sources' ? '-sources' : ''}-SHA256SUMS.txt`;
    const checksum = fs.readFileSync(path.join(directory, checksumName));
    if (checksum.toString('ascii').trim() !== `${digest}  ${name}`) throw new Error(`SDK checksum mismatch: ${name}`);
    return [{ name, data }, { name: checksumName, data: checksum }];
  }));
}

async function publish({ github, context, core, directory = 'sdk-assets' }) {
  const lock = readLock();
  if (!/^\d+\.\d+\.\d+$/.test(lock.version) || !/^[a-f0-9]{64}$/.test(lock.recipeSha256)) throw new Error('Invalid SDK version or recipe');
  const assets = readAssets(directory, lock);
  const tag = `native-sdk-v${lock.version}`;
  let release;
  try {
    release = (await github.rest.repos.getReleaseByTag({ ...context.repo, tag })).data;
    if (!release.draft) throw new Error(`SDK ${tag} already exists; published versions are never overwritten`);
    if (release.target_commitish !== context.sha || !String(release.body || '').includes(`Recipe SHA256: ${lock.recipeSha256}`)) {
      throw new Error('SDK draft belongs to another commit or recipe');
    }
  } catch (error) { if (error.status !== 404) throw error; }
  if (!release) release = (await github.rest.repos.createRelease({
    ...context.repo, tag_name: tag, target_commitish: context.sha, name: `ShenView native SDK ${lock.version}`,
    draft: true, prerelease: true, make_latest: 'false',
    body: `Windows x64, Release. Dependency SDK, separate from application releases.\n\nSource commit: ${context.sha}\nRecipe SHA256: ${lock.recipeSha256}\n\nSDK archives include headers, libraries, licenses and dependency build recipes. Companion source archives contain the exact HDR/FFmpeg source trees and recipes. Use the exact SDK asset SHA256 in native-sdk.lock.json.`,
  })).data;
  const oldAssets = await github.paginate(github.rest.repos.listReleaseAssets, { ...context.repo, release_id: release.id, per_page: 100 });
  for (const asset of oldAssets) {
    await github.rest.repos.deleteReleaseAsset({ ...context.repo, asset_id: asset.id });
  }
  for (const asset of assets) {
    await github.rest.repos.uploadReleaseAsset({ ...context.repo, release_id: release.id, ...asset });
  }
  await github.rest.repos.updateRelease({ ...context.repo, release_id: release.id, draft: false, prerelease: true, make_latest: 'false' });
  core.notice(`Published dependency SDK: ${release.html_url}`);
}

module.exports = { readLock, readAssets, publish };
