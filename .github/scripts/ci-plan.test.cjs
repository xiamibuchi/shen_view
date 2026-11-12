const { test } = require('node:test');
const assert = require('node:assert/strict');
const { planChecks } = require('./ci-plan.cjs');
const { validateGate } = require('./pr-gate.cjs');

test('only ordinary Markdown documentation can skip platform builds', () => {
  assert.deepEqual(planChecks(['README.md', 'docs/guide/open.md']),
    { windows_required: false, macos_required: false });
  for (const files of [[], ['docs/sample.ps1'], ['docs/guide/x.dart'], ['LICENSE'],
    ['.gitattributes'], ['.github/workflows/pr-checks.yml'], ['apps/viewer/pubspec.yaml'],
    ['docs/guide/open.md', 'apps/viewer/lib/main.dart'], ['apps/viewer/testdata/note.md']]) {
    assert.deepEqual(planChecks(files),
      { windows_required: true, macos_required: true }, JSON.stringify(files));
  }
});

const needs = (required, result) => ({
  plan: { result: 'success', outputs: {
    windows_required: required, macos_required: required,
  } },
  commits: { result: 'success' }, quick: { result }, windows: { result },
  macos: { result },
});
test('gate accepts only successful code checks or an explicit docs skip', () => {
  validateGate(needs('true', 'success'));
  validateGate(needs('false', 'skipped'));
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.throws(() => validateGate(needs('true', result)));
  }
  assert.throws(() => validateGate(needs(undefined, 'skipped')));
  assert.throws(() => validateGate({ ...needs('true', 'success'), quick: { result: 'failure' } }));
  assert.throws(() => validateGate({ ...needs('true', 'success'), macos: { result: 'failure' } }));
  assert.throws(() => validateGate({ ...needs('false', 'skipped'), macos: { result: 'success' } }));
  assert.throws(() => validateGate({ ...needs('true', 'success'), plan: {
    result: 'success', outputs: { windows_required: 'true' },
  } }));
  assert.throws(() => validateGate({ ...needs('false', 'skipped'), commits: { result: 'failure' } }));
  assert.throws(() => validateGate({ ...needs('false', 'skipped'), plan: { result: 'cancelled' } }));
});
