const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

function planChecks(files) {
  const docsOnly = files.length > 0 && files.every(file =>
    file === 'README.md' || /^docs\/(?:[^/]+\/)*[^/]+\.md$/.test(file));
  return { windows_required: !docsOnly, macos_required: !docsOnly };
}

if (require.main === module) {
  const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  // Include both names of a rename so moving source into docs cannot skip checks.
  const files = execFileSync('git', ['diff', '--name-only', '--no-renames', '-z',
    event.pull_request.base.sha, event.pull_request.head.sha], { encoding: 'utf8' })
    .split('\0').filter(Boolean);
  const plan = planChecks(files);
  fs.appendFileSync(process.env.GITHUB_OUTPUT, `windows_required=${plan.windows_required}\n`);
  fs.appendFileSync(process.env.GITHUB_OUTPUT, 'macos_required=' + plan.macos_required + '\n');
  console.log(JSON.stringify({ files, ...plan }, null, 2));
}

module.exports = { planChecks };
