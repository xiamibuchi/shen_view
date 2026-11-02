const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseVersion, validatePullRequest } = require('./pr-policy.cjs');
const pr = (base, head, title = 'ci: 配置发布流程') => ({
  title, base: { ref: base, repo: { full_name: 'xiamibuchi/shen_view' } },
  head: { ref: head, repo: { full_name: 'xiamibuchi/shen_view' } },
});
test('valid Windows version and build', () => {
  assert.deepEqual(parseVersion('version: 0.1.2+37\n'), { version: '0.1.2', build: 37, tag: 'v0.1.2' });
});
test('reject malformed, prerelease, overflow and leading-zero versions', () => {
  for (const version of ['0.1.0', '0.1.0-rc.1+1', '0.1.0+65536', '01.1.0+1']) {
    assert.throws(() => parseVersion('version: ' + version));
  }
});
test('work PR targets matching version branch', () => {
  validatePullRequest(pr('release/0.1.0', 'feat/open'), 'version: 0.1.0+1');
  assert.throws(() => validatePullRequest(pr('release/0.2.0', 'feat/open'), 'version: 0.1.0+1'));
});
test('main only accepts matching release branch from the same repository', () => {
  validatePullRequest(pr('main', 'release/0.1.0'), 'version: 0.1.0+1');
  assert.throws(() => validatePullRequest(pr('main', 'fix/open'), 'version: 0.1.0+1'));
  const fork = pr('main', 'release/0.1.0');
  fork.head.repo.full_name = 'someone/shen_view';
  assert.throws(() => validatePullRequest(fork, 'version: 0.1.0+1'));
});
test('squash title must satisfy commit format', () => {
  for (const title of ['Add feature', 'fix: ', 'Merge pull request #1']) {
    assert.throws(() => validatePullRequest(pr('release/0.1.0', 'feat/open', title), 'version: 0.1.0+1'));
  }
});
