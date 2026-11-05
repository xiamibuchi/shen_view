const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { readAssets, publish } = require('./native-sdk-release.cjs');

test('SDK publication validates assets and never replaces an existing version', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'shenview-sdk-release-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const lock = { components: {} };
  for (const component of ['hdr', 'ffmpeg']) {
    for (const kind of ['sdk', 'sources']) {
    const asset = `shenview-${component}-${kind}-windows-x64.zip`;
    const data = Buffer.from(component);
    if (kind === 'sdk') lock.components[component] = { asset };
    fs.writeFileSync(path.join(directory, asset), data);
    fs.writeFileSync(path.join(directory, `${component}${kind === 'sources' ? '-sources' : ''}-SHA256SUMS.txt`),
      `${crypto.createHash('sha256').update(data).digest('hex')}  ${asset}\n`);
    }
  }
  assert.equal(readAssets(directory, lock).length, 8);
  const calls = [];
  const github = { rest: { repos: {
    getReleaseByTag: async () => { const error = new Error('missing'); error.status = 404; throw error; },
    createRelease: async args => { calls.push(['create', args]); return { data: { id: 42, html_url: 'https://example.invalid/sdk' } }; },
    uploadReleaseAsset: async args => { calls.push(['upload', args]); },
    updateRelease: async args => { calls.push(['publish', args]); },
    listReleaseAssets: async () => ({ data: [] }),
    deleteReleaseAsset: async args => { calls.push(['delete', args]); },
  } } };
  github.paginate = async () => [];
  const context = { repo: { owner: 'xiamibuchi', repo: 'shen_view' }, sha: 'a'.repeat(40) };
  await publish({ github, context, core: { notice() {} }, directory });
  assert.deepEqual(calls.map(c => c[0]), ['create', ...Array(8).fill('upload'), 'publish']);
  assert.equal(calls[0][1].draft, true);
  assert.equal(calls[0][1].make_latest, 'false');
  assert.equal(calls.at(-1)[1].draft, false);
  assert.equal(calls.at(-1)[1].make_latest, 'false');
  github.rest.repos.getReleaseByTag = async () => ({ data: { id: 42 } });
  calls.length = 0;
  await assert.rejects(publish({ github, context, core: { notice() {} }, directory }), /never overwritten/);
  assert.equal(calls.length, 0);
  github.rest.repos.getReleaseByTag = async () => ({ data: { id: 42, draft: true, target_commitish: 'other', body: '' } });
  await assert.rejects(publish({ github, context, core: { notice() {} }, directory }), /another commit/);
  assert.equal(calls.length, 0);
  const recipeSha = JSON.parse(fs.readFileSync('third_party/native-sdk.lock.json', 'utf8')).recipeSha256;
  github.rest.repos.getReleaseByTag = async () => ({ data: { id: 42, draft: true, target_commitish: context.sha, body: `Recipe SHA256: ${recipeSha}` } });
  github.paginate = async () => [{ id: 123 }];
  await publish({ github, context, core: { notice() {} }, directory });
  assert.deepEqual(calls.map(c => c[0]), ['delete', ...Array(8).fill('upload'), 'publish']);
  fs.writeFileSync(path.join(directory, lock.components.hdr.asset), 'corrupt');
  assert.throws(() => readAssets(directory, lock), /checksum mismatch/);
});
