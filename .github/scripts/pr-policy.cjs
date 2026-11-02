const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const subject = /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^()\s]+\))?!?: \S(?:.*\S)?$/u;

function parseVersion(text) {
  const match = /^version:\s*((0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))\+(0|[1-9]\d*)\s*$/m.exec(text);
  if (!match || match.slice(2, 6).some(value => Number(value) > 65535)) {
    throw new Error('pubspec.yaml must use major.minor.patch+build, each Windows field <= 65535');
  }
  return { version: match[1], build: Number(match[5]), tag: 'v' + match[1] };
}

function validatePullRequest(pr, text) {
  if (!subject.test(pr.title)) throw new Error('PR title must follow Conventional Commits');
  const version = parseVersion(text);
  const target = pr.base.ref === 'main' ? pr.head.ref : pr.base.ref;
  if (target !== 'release/' + version.version) {
    throw new Error('PR must target its release/<version>; main only accepts release/<version>');
  }
  if (pr.base.ref === 'main' && pr.head.repo.full_name !== pr.base.repo.full_name) {
    throw new Error('Release PR must come from this repository');
  }
  return version;
}

function validateProgress(next, previous) {
  const a = next.version.split('.').map(Number).concat(next.build);
  const b = previous.version.split('.').map(Number).concat(previous.build);
  for (let i = 0; i < a.length; i++) {
    if (a[i] > b[i]) return;
    if (a[i] < b[i]) throw new Error('Version must not decrease relative to the target branch');
  }
}

if (require.main === module) {
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  const result = validatePullRequest(event.pull_request, fs.readFileSync('apps/viewer/pubspec.yaml', 'utf8'));
  const previous = parseVersion(execFileSync('git', ['show', event.pull_request.base.sha + ':apps/viewer/pubspec.yaml'], { encoding: 'utf8' }));
  validateProgress(result, previous);
  if (event.pull_request.base.ref === 'main') {
    try {
      execFileSync('git', ['rev-parse', '--verify', 'refs/tags/' + result.tag], { stdio: 'ignore' });
    } catch {
      console.log('Release policy passed: ' + result.tag);
      process.exit(0);
    }
    throw new Error('Release tag already exists: ' + result.tag);
  }
  console.log('PR policy passed: ' + result.version + '+' + result.build);
}

module.exports = { parseVersion, validatePullRequest, validateProgress };
