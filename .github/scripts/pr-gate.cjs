function validateGate(needs) {
  for (const name of ['plan', 'commits']) {
    if (needs[name]?.result !== 'success') throw new Error(`${name} must succeed`);
  }
  const required = needs.plan.outputs?.windows_required;
  if (!['true', 'false'].includes(required)) throw new Error('Missing CI plan');
  const expected = required === 'true' ? 'success' : 'skipped';
  if (needs.windows?.result !== expected) throw new Error(`Windows result must be ${expected}`);
}

if (require.main === module) validateGate(JSON.parse(process.env.CI_NEEDS));
module.exports = { validateGate };
