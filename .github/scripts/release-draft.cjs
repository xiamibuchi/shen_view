const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { readSourceDelivery, verifySourceLinks } = require('./source-delivery.cjs');

function draftBody(previous, manifest, delivery, pr) {
  const start = '<!-- shenview-source-links:start -->';
  const end = '<!-- shenview-source-links:end -->';
  const links = [start, '### Sources / 源码与许可', '',
    '[ShenView source and helpers / 本版本源码](' + delivery.source.url + ')',
    '[Source ZIP / 源码下载](' + delivery.source.archiveUrl + ')',
    '[Licenses, rebuilding and replacement / 许可、重建与替换说明](' + delivery.source.instructionsUrl + ')',
    '', ...delivery.assets.filter(asset => asset.location === 'remote').map(asset => '- [' + asset.name + '](' + asset.url + ')'),
    '', 'SOURCES.json records exact source links, SHA256, sizes and matching binary hashes.',
    '源码在固定提交或依赖版本中集中保存；无需重复下载，普通用户只需应用便携 ZIP。',
    'SOURCES-SHA256SUMS.txt verifies the source index and bundled notices snapshot.', end].join('\n');
  let body = previous || [
    'Windows x64 portable preview (unsigned). / Windows x64 未签名便携预览版。', '',
    'Source commit: ' + manifest.sourceCommit, 'Release PR: #' + pr.number, '',
    'Extract the entire ZIP before running ShenView.exe. Complex SVG requires WebView2 Runtime.',
    '完整解压后以普通权限运行。未签名程序可能出现 SmartScreen 提示；请勿关闭系统安全防护。',
    'HDR is experimental; physical highlights, cross-screen transitions and recovery remain unverified.',
    'HDR 为实验功能，实屏高光、跨屏与恢复尚未验收。此版本不提供安装器或 MSIX。', '',
    'Before publishing: verify the final package in a clean environment, source links, notices and bilingual release notes.',
    '公开前仍须完成最终包复验、附件与源码链接核对及中英文说明审阅。',
    'This draft does not certify that release acceptance is complete.',
  ].join('\n');
  body = body.replace(/^Source commit: .+$/m, 'Source commit: ' + manifest.sourceCommit)
    .replace(/^Release PR: #\d+$/m, 'Release PR: #' + pr.number)
    .replace(/^Source delivery: download every source asset listed in SOURCES.json from this same release\.\r?\n?/m, '')
    .replace(/^See SOURCES.md for licenses, rebuilding, component replacement and known runtime requirements\.\r?\n?/m, '')
    .replace('- Complete minimum-Windows, clean-environment and physical-HDR acceptance.',
      '- Verify the final portable package in a clean environment. HDR remains experimental; physical-HDR acceptance is deferred.')
    .replace('- Verify all source assets and third-party notices against SOURCES-SHA256SUMS.txt.',
      '- Verify linked sources against SOURCES.json and local index/notices against SOURCES-SHA256SUMS.txt.');
  const from = body.indexOf(start);
  const to = body.indexOf(end);
  if ((from < 0) !== (to < 0) || (from >= 0 && to < from)) throw new Error('Malformed source-links section');
  return from < 0 ? body.trimEnd() + '\n\n' + links : body.slice(0, from) + links + body.slice(to + end.length);
}

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
  const { uploads: sourceAssets, delivery } = readSourceDelivery('release-artifact', manifest);
  await verifySourceLinks(github, delivery);
  if (pr.head.ref !== 'release/' + manifest.version) throw new Error('Release branch and artifact version differ');
  const repo = context.repo;
  const releases = await github.paginate(github.rest.repos.listReleases, { ...repo, per_page: 100 });
  let release = releases.find(item => item.tag_name === tag);
  if (release && !release.draft) throw new Error('Refusing to change a published release');
  let tagged = false;
  try {
    const ref = await github.rest.git.getRef({ ...repo, ref: 'tags/' + tag });
    tagged = true;
    if (!release || ref.data.object.sha !== mergedSha) {
      throw new Error('Refusing to reuse an existing release tag');
    }
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  if (release && release.target_commitish !== mergedSha) {
    if (tagged || !/^[a-f0-9]{40}$/.test(release.target_commitish)) throw new Error('Refusing to advance a tagged or unpinned draft');
    const main = (await github.rest.git.getRef({ ...repo, ref: 'heads/main' })).data;
    const comparison = (await github.rest.repos.compareCommitsWithBasehead({ ...repo, basehead: release.target_commitish + '...' + mergedSha })).data;
    if (main.object.sha !== mergedSha || comparison.status !== 'ahead' || comparison.behind_by !== 0) {
      throw new Error('Draft may only advance to a descendant on current main');
    }
  }
  const body = draftBody(release?.body, manifest, delivery, pr);
  if (!release) {
    release = (await github.rest.repos.createRelease({
      ...repo, tag_name: tag, target_commitish: mergedSha,
      name: tag + ' — Windows 预览版', draft: true, prerelease: true, body,
    })).data;
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, { ...repo, release_id: release.id, per_page: 100 });
  const uploads = [manifest.package, 'SHA256SUMS.txt', 'release.json'].map(name => ({ name, file: path.join(directory, name) })).concat(sourceAssets);
  for (const { name, file } of uploads) {
    const old = assets.find(asset => asset.name === name);
    if (old) await github.rest.repos.deleteReleaseAsset({ ...repo, asset_id: old.id });
    await github.rest.repos.uploadReleaseAsset({
      ...repo, release_id: release.id, name,
      data: fs.readFileSync(file),
    });
  }
  // Remove only obsolete generated attachments after every replacement has uploaded.
  const obsolete = new Set(delivery.assets.filter(asset => asset.location === 'remote').map(asset => asset.name)
    .concat(['ShenView-' + manifest.windowsVersion + '-source.zip', 'SOURCES.md']));
  for (const asset of assets.filter(asset => obsolete.has(asset.name))) {
    await github.rest.repos.deleteReleaseAsset({ ...repo, asset_id: asset.id });
  }
  await github.rest.repos.updateRelease({ ...repo, release_id: release.id, target_commitish: mergedSha, body, draft: true, prerelease: true });
  core.notice('Draft ready: ' + release.html_url);
}

module.exports = { readArtifact, createDraft, draftBody };
