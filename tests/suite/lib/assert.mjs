export class SuiteError extends Error {
  constructor(message, detail) {
    super(message);
    this.detail = detail;
  }
}

export function ok(cond, message, detail) {
  if (!cond) throw new SuiteError(message, detail);
}

export function eq(actual, expected, message) {
  if (actual !== expected) {
    throw new SuiteError(message || `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`, { actual, expected });
  }
}

let pass = 0;
let fail = 0;
const failures = [];

export async function step(name, fn) {
  const t0 = Date.now();
  try {
    await fn();
    pass += 1;
    console.log(`  ✓ ${name} (${Date.now() - t0}ms)`);
  } catch (err) {
    fail += 1;
    failures.push({ name, err });
    console.error(`  ✗ ${name} (${Date.now() - t0}ms)`);
    console.error(`    ${err.message}`);
    if (err.detail) console.error(`    ${typeof err.detail === 'string' ? err.detail : JSON.stringify(err.detail).slice(0, 400)}`);
  }
}

export function summary() {
  console.log('');
  console.log(`Resultaat: ${pass} ok, ${fail} mislukt`);
  return { pass, fail, failures };
}
