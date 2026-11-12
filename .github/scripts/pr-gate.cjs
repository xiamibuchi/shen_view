function validateGate(needs) {
  for (const name of ['plan', 'commits']) {
    if (needs[name]?.result !== 'success') throw new Error(`${name} must succeed`);
  }
  const windowsRequired = needs.plan.outputs?.windows_required;
  const macosRequired = needs.plan.outputs?.macos_required;
  if (!['true', 'false'].includes(windowsRequired) ||
      !['true', 'false'].includes(macosRequired) ||
      windowsRequired !== macosRequired) throw new Error('Missing CI plan');
  const expected = windowsRequired === 'true' ? 'success' : 'skipped';
  for (const name of ['quick', 'windows', 'macos']) {
    if (needs[name]?.result !== expected) throw new Error(`${name} result must be ${expected}`);
  }
}

if (require.main === module) validateGate(JSON.parse(process.env.CI_NEEDS));
module.exports = { validateGate };
