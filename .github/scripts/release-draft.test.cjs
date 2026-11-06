const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { readArtifact, createDraft, draftBody } = require('./release-draft.cjs');
const { sourceFixture } = require('./release-test-fixture.cjs');

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
    fs.writeFileSync(path.join(root, manifest.package + '.sha256'), crypto.createHash('sha256').update(zip).digest('hex') + '  ' + manifest.package + '\n');
    write();
    assert.equal(readArtifact(root, 'abc123').tag, 'v0.1.0');
    fs.renameSync(path.join(root, manifest.package + '.sha256'), path.join(root, 'SHA256SUMS.txt'));
    assert.throws(() => readArtifact(root, 'abc123'), /ENOENT/);
    fs.renameSync(path.join(root, 'SHA256SUMS.txt'), path.join(root, manifest.package + '.sha256'));
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

test('publisher links shared sources, uploads six local assets and refuses published releases', async () => {
  const previous = process.cwd();
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-publisher-'));
  fs.mkdirSync(path.join(root, 'release-artifact'));
  const directory = path.join(root, 'release-artifact');
  const sha = 'c'.repeat(40);
  const manifest = { version: '0.1.0', windowsVersion: '0.1.0.1', sourceCommit: sha,
    sourceDirty: false, installerType: 'portable', package: 'ShenView-0.1.0.1-windows-x64-portable.zip' };
  fs.writeFileSync(path.join(directory, 'release.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(directory, manifest.package), 'zip');
  fs.writeFileSync(path.join(directory, manifest.package + '.sha256'), crypto.createHash('sha256').update('zip').digest('hex') + '  ' + manifest.package);
  const source = sourceFixture(root, manifest);
  const context = { repo: { owner: 'xiamibuchi', repo: 'shen_view' }, payload: { pull_request: {
    merged: true, number: 8, merge_commit_sha: sha,
    head: { ref: 'release/0.1.0', repo: { full_name: 'xiamibuchi/shen_view' } },
    base: { ref: 'main', repo: { full_name: 'xiamibuchi/shen_view' } },
  } } };
  let existing = [];
  let appAssets = [];
  let sourceAvailable = true;
  let tagged = false;
  let comparison = { status: 'ahead', behind_by: 0 };
  let mainSha = sha;
  const writes = [];
  const deleted = [];
  const listReleases = () => {};
  const github = {
    paginate: async (fn, args) => fn === listReleases ? existing : args.release_id === 1 ? appAssets :
      source.delivery.assets.filter(asset => asset.location === 'remote').map(asset => ({
        name: asset.name, size: asset.bytes, state: 'uploaded', digest: 'sha256:' + asset.sha256,
      })),
    rest: { git: {
      getCommit: async () => ({ data: { sha } }),
      getRef: async args => {
        if (args.ref === 'heads/main') return { data: { object: { sha: mainSha } } };
        if (tagged) return { data: { object: { sha } } };
        throw Object.assign(new Error('not found'), { status: 404 });
      },
    }, repos: {
      listReleases, listReleaseAssets() {},
      getReleaseByTag: async args => {
        if (!sourceAvailable) throw Object.assign(new Error('source unavailable'), { status: 404 });
        return { data: { id: 2, draft: false, tag_name: args.tag } };
      },
      compareCommitsWithBasehead: async () => ({ data: comparison }),
      createRelease: async args => { writes.push(args); return { data: { id: 1, html_url: 'draft-url' } }; },
      uploadReleaseAsset: async args => { writes.push(args); },
      updateRelease: async args => { writes.push(args); },
      deleteReleaseAsset: async args => { deleted.push({ ...args, afterWrites: writes.length }); },
    } },
  };
  try {
    process.chdir(root);
    await createDraft({ github, context, core: { notice() {} } });
    assert.equal(writes[0].draft, true);
    assert.equal(writes[0].target_commitish, sha);
    assert.equal(writes.length, 8);
    assert.match(writes[0].body, /unsigned|Unsigned/);
    assert.ok(writes.some(write => write.name === 'SOURCES.json'));
    assert.ok(writes.some(write => write.name === manifest.package + '.sha256'));
    assert.ok(!writes.some(write => write.name === 'SHA256SUMS.txt'));
    assert.ok(!writes.some(write => write.name === 'imagemagick-windows.zip'));
    assert.match(writes[0].body, /third-party-sources-v1/);
    assert.match(writes[0].body, /HDR is experimental/);
    existing = [{ tag_name: 'v0.1.0', draft: false, target_commitish: sha }];
    await assert.rejects(createDraft({ github, context, core: {} }));
    existing = [{ tag_name: 'v0.1.0', draft: true, target_commitish: 'other' }];
    await assert.rejects(createDraft({ github, context, core: {} }));
    assert.equal(writes.length, 8);
    existing = [{ id: 1, tag_name: 'v0.1.0', draft: true, target_commitish: 'a'.repeat(40),
      body: 'Source commit: old\nRelease PR: #29\nMaintainer notes: keep me' }];
    appAssets = [{ id: 20, name: 'SOURCES.md' }, { id: 21, name: 'imagemagick-windows.zip' },
      { id: 22, name: 'ShenView-0.1.0.1-source.zip' }, { id: 23, name: 'custom-notes.pdf' },
      { id: 24, name: 'SHA256SUMS.txt' }];
    await createDraft({ github, context, core: { notice() {} } });
    assert.equal(writes.length, 15);
    assert.equal(writes.at(-1).target_commitish, sha);
    assert.equal(writes.at(-1).draft, true);
    assert.match(writes.at(-1).body, /Maintainer notes: keep me/);
    assert.deepEqual(deleted.map(asset => asset.asset_id), [20, 21, 22, 24]);
    assert.ok(deleted.every(asset => asset.afterWrites === 14));
    comparison = { status: 'diverged', behind_by: 1 };
    await assert.rejects(createDraft({ github, context, core: {} }), /descendant/);
    comparison = { status: 'ahead', behind_by: 0 };
    mainSha = 'b'.repeat(40);
    await assert.rejects(createDraft({ github, context, core: {} }), /descendant/);
    mainSha = sha;
    tagged = true;
    await assert.rejects(createDraft({ github, context, core: {} }), /tagged/);
    tagged = false;
    sourceAvailable = false;
    await assert.rejects(createDraft({ github, context, core: {} }), /unavailable/);
    sourceAvailable = true;
    fs.rmSync(path.join(source.sourceDirectory, 'SOURCES.json'));
    await assert.rejects(createDraft({ github, context, core: {} }), /exactly one source/);
    assert.equal(writes.length, 15);
  } finally { process.chdir(previous); fs.rmSync(root, { recursive: true }); }
});

test('release layout puts downloads first, migrates legacy text and preserves maintainer notes', () => {
  const manifest = { version: '0.1.0', windowsVersion: '0.1.0.1',
    package: 'ShenView-0.1.0.1-windows-x64-portable.zip', sourceCommit: 'c'.repeat(40) };
  const delivery = { source: { url: 'tree', archiveUrl: 'archive', instructionsUrl: 'instructions' }, assets: [] };
  const legacy = 'Source commit: old\nRelease PR: #29\n' +
    'Source delivery: download every source asset listed in SOURCES.json from this same release.\n' +
    'See SOURCES.md for licenses, rebuilding, component replacement and known runtime requirements.\n' +
    '- Complete minimum-Windows, clean-environment and physical-HDR acceptance.\nMaintainer notes';
  const body = draftBody(legacy, manifest, delivery, { number: 31 });
  assert.match(body, /Release PR: \[\#31\]/);
  assert.ok(!body.includes('See SOURCES.md'));
  assert.match(body, /HDR is experimental/);
  assert.match(body, /portable\.zip\.sha256/);
  assert.ok(!body.includes('Before publishing'));
  assert.ok(body.indexOf('## 下载') < body.indexOf('## 本版主要功能'));
  assert.ok(body.indexOf('## 本版主要功能') < body.indexOf('## 使用说明'));
  assert.ok(body.indexOf('## 使用说明') < body.indexOf('## 源码与许可'));
  assert.match(body, /<summary>English<\/summary>/);
  assert.match(body, /Maintainer notes/);
  assert.equal(draftBody(body, manifest, delivery, { number: 31 }), body);
  const updated = draftBody('Custom intro\n' + body, manifest, delivery, { number: 33 });
  assert.ok(updated.startsWith('Custom intro\n'));
  assert.match(updated, /pull\/33/);
  assert.ok(!updated.includes('pull/31'));
  assert.match(updated, /Maintainer notes/);
  assert.throws(() => draftBody('<!-- shenview-release:start -->', manifest, delivery, {}), /Malformed/);
  assert.throws(() => draftBody('<!-- shenview-source-links:start -->', manifest, delivery, {}), /Malformed/);
});
