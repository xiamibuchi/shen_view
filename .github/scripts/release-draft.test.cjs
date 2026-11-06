const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { readArtifact, createDraft } = require('./release-draft.cjs');
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

test('publisher creates only a draft and refuses published releases or another SHA', async () => {
  const previous = process.cwd();
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-publisher-'));
  fs.mkdirSync(path.join(root, 'release-artifact'));
  const directory = path.join(root, 'release-artifact');
  const manifest = { version: '0.1.0', windowsVersion: '0.1.0.1', sourceCommit: 'merged',
    sourceDirty: false, installerType: 'portable', package: 'ShenView-0.1.0.1-windows-x64-portable.zip' };
  fs.writeFileSync(path.join(directory, 'release.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(directory, manifest.package), 'zip');
  fs.writeFileSync(path.join(directory, 'SHA256SUMS.txt'), crypto.createHash('sha256').update('zip').digest('hex') + '  ' + manifest.package);
  const source = sourceFixture(root, manifest);
  const context = { repo: { owner: 'xiamibuchi', repo: 'shen_view' }, payload: { pull_request: {
    merged: true, number: 8, merge_commit_sha: 'merged',
    head: { ref: 'release/0.1.0', repo: { full_name: 'xiamibuchi/shen_view' } },
    base: { ref: 'main', repo: { full_name: 'xiamibuchi/shen_view' } },
  } } };
  let existing = [];
  const writes = [];
  const listReleases = () => {};
  const github = {
    paginate: async fn => fn === listReleases ? existing : [],
    rest: { git: { getRef: async () => { throw Object.assign(new Error('not found'), { status: 404 }); } }, repos: {
      listReleases, listReleaseAssets() {},
      createRelease: async args => { writes.push(args); return { data: { id: 1, html_url: 'draft-url' } }; },
      uploadReleaseAsset: async args => { writes.push(args); },
    } },
  };
  try {
    process.chdir(root);
    await createDraft({ github, context, core: { notice() {} } });
    assert.equal(writes[0].draft, true);
    assert.equal(writes[0].target_commitish, 'merged');
    assert.equal(writes.length, 13);
    assert.match(writes[0].body, /unsigned|Unsigned/);
    assert.ok(writes.some(write => write.name === 'SOURCES.json'));
    assert.ok(writes.some(write => write.name === 'imagemagick-windows.zip'));
    existing = [{ tag_name: 'v0.1.0', draft: false, target_commitish: 'merged' }];
    await assert.rejects(createDraft({ github, context, core: {} }));
    existing = [{ tag_name: 'v0.1.0', draft: true, target_commitish: 'other' }];
    await assert.rejects(createDraft({ github, context, core: {} }));
    assert.equal(writes.length, 13);
    fs.rmSync(path.join(source.sourceDirectory, 'SOURCES.json'));
    await assert.rejects(createDraft({ github, context, core: {} }), /exactly one source/);
    assert.equal(writes.length, 13);
  } finally { process.chdir(previous); fs.rmSync(root, { recursive: true }); }
});
