const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function readArtifact(root, expectedSha) {
  const entries = fs.readdirSync(root, { recursive: true });
  const manifests = entries.filter(name => path.basename(name) === 'release.json');
  if (manifests.length !== 1) throw new Error('Expected exactly one release manifest');
  const directory = path.dirname(path.join(root, manifests[0]));
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, 'release.json'), 'utf8'));
  if (manifest.sourceCommit !== expectedSha || manifest.sourceDirty !== false || manifest.installerType !== 'portable') {
    throw new Error('Artifact is not a clean build of the merged commit');
  }
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(manifest.version) ||
      !new RegExp('^' + manifest.version.replaceAll('.', '\\.') + '\\.[0-9]+$').test(manifest.windowsVersion) ||
      manifest.package !== 'ShenView-' + manifest.windowsVersion + '-windows-x64-portable.zip') {
    throw new Error('Unexpected release version or package name');
  }
  const packagePath = path.join(directory, manifest.package);
  const hash = crypto.createHash('sha256').update(fs.readFileSync(packagePath)).digest('hex');
  const checksum = fs.readFileSync(path.join(directory, 'SHA256SUMS.txt'), 'utf8').trim();
  if (checksum !== hash + '  ' + manifest.package) throw new Error('Package checksum mismatch');
  return { manifest, directory, tag: 'v' + manifest.version };
}

async function createDraft({ github, context, core }) {
  const pr = context.payload.pull_request;
  const mergedSha = pr.merge_commit_sha;
  if (!pr.merged || pr.base.ref !== 'main' || pr.head.repo.full_name !== pr.base.repo.full_name) {
    throw new Error('Only merged release PRs from this repository can create drafts');
  }
  const { manifest, directory, tag } = readArtifact('release-artifact', mergedSha);
  if (pr.head.ref !== 'release/' + manifest.version) throw new Error('Release branch and artifact version differ');
  const repo = context.repo;
  const releases = await github.paginate(github.rest.repos.listReleases, { ...repo, per_page: 100 });
  let release = releases.find(item => item.tag_name === tag);
  if (release && (!release.draft || release.target_commitish !== mergedSha)) {
    throw new Error('Refusing to change a published release or draft for another commit');
  }
  try {
    const ref = await github.rest.git.getRef({ ...repo, ref: 'tags/' + tag });
    if (!release || ref.data.object.sha !== mergedSha) {
      throw new Error('Refusing to reuse an existing release tag');
    }
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  if (!release) {
    const body = [
      'Windows x64 portable preview (unsigned).',
      '',
      'Source commit: ' + mergedSha,
      'Release PR: #' + pr.number,
      '',
      'Before publishing:',
      '- Complete minimum-Windows, clean-environment and physical-HDR acceptance.',
      '- Complete third-party corresponding-source delivery and license review.',
      '- Confirm unsigned-package notices, known limitations and release notes.',
      '',
      'Extract the entire ZIP. Complex SVG requires WebView2 Runtime.',
      'This draft is not evidence that release acceptance is complete.',
    ].join('\n');
    release = (await github.rest.repos.createRelease({
      ...repo, tag_name: tag, target_commitish: mergedSha,
      name: tag + ' — Windows 预览版', draft: true, prerelease: true, body,
    })).data;
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { ...repo, release_id: release.id, per_page: 100 });
  for (const name of [manifest.package, 'SHA256SUMS.txt', 'release.json']) {
    const old = assets.find(asset => asset.name === name);
    if (old) await github.rest.repos.deleteReleaseAsset({ ...repo, asset_id: old.id });
    await github.rest.repos.uploadReleaseAsset({
      ...repo, release_id: release.id, name,
      data: fs.readFileSync(path.join(directory, name)),
    });
  }
  core.notice('Draft ready: ' + release.html_url);
}

module.exports = { readArtifact, createDraft };
