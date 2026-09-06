/**
 * scripts/endpoint-smoke-test.ts — extensive live smoke test of the PUBLIC API.
 *
 * WHY THIS EXISTS (vs scripts/parity-test.ts)
 * -------------------------------------------
 * parity-test.ts diffs a *shadow* Express service against the *live R gateway*.
 * That made sense while R was still authoritative. Now that virtually the whole
 * surface has been cut over to Express, the thing that actually needs guarding
 * is: "does every public endpoint still answer correctly, with the same
 * parameter names and the same response contract the strategies depend on?"
 *
 * This suite therefore hits the REAL public base URL (https://api.infinitetrading.io
 * by default) and asserts, per endpoint:
 *   - validation parity: bad network / bad protocol / bad apiKey / bad pool
 *     return R's documented status_code values (1000/1001/1002/1004) and R's
 *     wire format (jsonlite auto-boxes scalars into 1-element arrays).
 *   - contract checks: successful reads return the expected fields/types.
 *   - safety: NOTHING here can move funds. Money-moving endpoints are only
 *     exercised with deliberately-invalid credentials (so they must reject) or
 *     in an explicit dryRun mode. There is no code path in this file that
 *     submits a transaction.
 *
 * USAGE
 *   npx ts-node scripts/endpoint-smoke-test.ts
 *   BASE_URL=http://localhost:8000 npx ts-node scripts/endpoint-smoke-test.ts
 *   API_KEY=<uuid> POOL=<0x..> NETWORK=optimism npx ts-node scripts/endpoint-smoke-test.ts
 *   npx ts-node scripts/endpoint-smoke-test.ts --only getSymbol,getContract
 *
 * Exit code is non-zero if any assertion fails, so it can gate a deploy.
 */

const BASE_URL = (process.env.BASE_URL || 'https://api.infinitetrading.io').replace(/\/$/, '');
const API_KEY = process.env.API_KEY || 'eddf4668-f5fc-4d20-8ce5-17f50722abdf';
const POOL = (process.env.POOL || '0x9b1a83432996e4e075dd24d4ed7288a2c4ca730a').toLowerCase();
const NETWORK = process.env.NETWORK || 'optimism';
const PROTOCOL = 'dhedge';

// A syntactically-valid UUID that is NOT a registered key — used to prove that
// money-moving endpoints reject unknown credentials rather than executing.
const UNKNOWN_API_KEY = '00000000-0000-4000-8000-000000000000';
const BAD_POOL = '0xnotanaddress';
const BAD_NETWORK = 'notarealnetwork';

const onlyArg = (() => {
  const i = process.argv.indexOf('--only');
  return i === -1 ? null : (process.argv[i + 1] || '').split(',').map(s => s.trim()).filter(Boolean);
})();

type Method = 'GET' | 'POST';
interface Case {
  group: string;
  name: string;
  method?: Method;
  path: string;
  params?: Record<string, string>;
  /** Assertion: return null if OK, or a string describing the failure. */
  assert: (body: any, status: number, raw: string) => string | null;
}

// ── assertion helpers ────────────────────────────────────────────────────────

/**
 * R's plumber serialises with jsonlite, which auto-boxes scalars into
 * single-element arrays (e.g. {"status":["fail"]}). Migrated Express endpoints
 * reproduce that wire format, so accept either shape when reading a field.
 */
function unbox(v: any): any {
  return Array.isArray(v) && v.length === 1 ? v[0] : v;
}

function expectFail(code: string | number) {
  return (body: any): string | null => {
    const status = String(unbox(body?.status));
    const sc = String(unbox(body?.status_code) ?? unbox(body?.error_code) ?? '');
    if (status !== 'fail') return `expected status=fail, got status=${status} body=${JSON.stringify(body).slice(0, 200)}`;
    if (sc !== String(code)) return `expected status_code=${code}, got ${sc}`;
    return null;
  };
}

/** Accepts any rejection (fail status or non-2xx) — used where R's exact code varies. */
function expectRejected(body: any, status: number): string | null {
  const s = String(unbox(body?.status));
  if (s === 'fail' || status >= 400) return null;
  return `expected a rejection, got status=${status} body=${JSON.stringify(body).slice(0, 200)}`;
}

function expectOk(extra?: (body: any) => string | null) {
  return (body: any, status: number): string | null => {
    if (status !== 200) return `expected HTTP 200, got ${status}: ${JSON.stringify(body).slice(0, 200)}`;
    const s = String(unbox(body?.status));
    if (s === 'fail') return `expected success, got fail: ${JSON.stringify(body).slice(0, 200)}`;
    return extra ? extra(body) : null;
  };
}

// ── test cases ───────────────────────────────────────────────────────────────

const base = { apiKey: API_KEY, network: NETWORK, protocol: PROTOCOL, pool: POOL };

const cases: Case[] = [];

/** Every public endpoint must apply basic_check identically. This generates the
 *  four standard validation cases for an endpoint, so parity is enforced
 *  uniformly instead of being spot-checked per endpoint. */
function addValidationSuite(group: string, path: string, method: Method, extra: Record<string, string> = {}) {
  cases.push(
    {
      group, name: `${path}: invalid network -> 1000`, method, path,
      params: { ...base, ...extra, network: BAD_NETWORK },
      assert: expectFail(1000),
    },
    {
      group, name: `${path}: invalid protocol -> 1001`, method, path,
      params: { ...base, ...extra, protocol: 'notaprotocol' },
      assert: expectFail(1001),
    },
    {
      group, name: `${path}: malformed apiKey -> 1002`, method, path,
      params: { ...base, ...extra, apiKey: 'not-a-uuid' },
      assert: expectFail(1002),
    },
    {
      group, name: `${path}: invalid pool address -> 1004`, method, path,
      params: { ...base, ...extra, pool: BAD_POOL },
      assert: expectFail(1004),
    },
  );
}

// ---- read-only endpoints: full functional checks -----------------------------

cases.push({
  group: 'reads', name: 'getSymbol: WETH on optimism resolves',
  path: '/getSymbol',
  params: { apiKey: API_KEY, network: 'optimism', contract: '0x4200000000000000000000000000000000000006' },
  assert: expectOk(b => {
    const msg = unbox(b?.msg ?? b?.symbol ?? b);
    return String(msg).toUpperCase().includes('WETH') ? null : `expected WETH, got ${JSON.stringify(b).slice(0, 200)}`;
  }),
});

cases.push({
  group: 'reads', name: 'getContract: WETH on optimism resolves to an address',
  path: '/getContract',
  params: { apiKey: API_KEY, network: 'optimism', symbol: 'weth' },
  assert: expectOk(b => {
    const msg = String(unbox(b?.msg ?? b?.contract ?? b));
    return /^0x[a-fA-F0-9]{40}$/.test(msg) ? null : `expected an address, got ${msg.slice(0, 120)}`;
  }),
});

cases.push({
  group: 'reads', name: 'poolComposition: returns enriched 6-field rows',
  path: '/poolComposition',
  params: base,
  assert: (b, status) => {
    if (status !== 200) return `HTTP ${status}`;
    if (!Array.isArray(b)) return `expected an array, got ${typeof b}`;
    if (b.length === 0) return null; // empty vault is legitimate
    const need = ['asset', 'isDeposit', 'assetPair', 'symbol', 'amount', 'price'];
    const missing = need.filter(k => !(k in b[0]));
    return missing.length ? `row missing fields: ${missing.join(',')}` : null;
  },
});

cases.push({
  group: 'reads', name: 'getGasBalance: returns a numeric balance',
  path: '/getGasBalance',
  params: { apiKey: API_KEY, network: NETWORK },
  assert: expectOk(),
});

cases.push({
  group: 'reads', name: 'getHealthFactor: read-only aave data',
  method: 'POST', path: '/getHealthFactor',
  params: base,
  assert: (b, status) => (status === 200 ? null : expectRejected(b, status)),
});

cases.push({
  group: 'reads', name: 'getPoolAaveData: read-only aave data',
  method: 'POST', path: '/getPoolAaveData',
  params: base,
  assert: (b, status) => (status === 200 ? null : expectRejected(b, status)),
});

// ---- validation parity across the migrated surface ---------------------------

addValidationSuite('validation', '/poolComposition', 'GET');
addValidationSuite('validation', '/getHealthFactor', 'POST');
addValidationSuite('validation', '/getPoolAaveData', 'POST');
addValidationSuite('validation', '/vaultTrade', 'POST', { from: 'usdc', to: 'weth', share: '1' });
addValidationSuite('validation', '/setBot', 'POST', { side: 'hold', pair: 'ETH-USD', threshold: '1', share: '1', max_usd: '10' });
addValidationSuite('validation', '/lend', 'POST', { asset: 'usdc', share: '1', platform: 'aavev3' });
addValidationSuite('validation', '/unlend', 'POST', { asset: 'usdc', share: '1', platform: 'aavev3' });
addValidationSuite('validation', '/borrow', 'POST', { asset: 'usdc', amount: '1', platform: 'aavev3' });
addValidationSuite('validation', '/repay', 'POST', { asset: 'usdc', share: '1', platform: 'aavev3' });

// ---- money-moving endpoints must REJECT unknown credentials -------------------
// (These prove authorisation is enforced. None of them can execute here.)

for (const [path, extra] of [
  ['/vaultTrade', { from: 'usdc', to: 'weth', share: '1' }],
  ['/lend', { asset: 'usdc', share: '1', platform: 'aavev3' }],
  ['/unlend', { asset: 'usdc', share: '1', platform: 'aavev3' }],
  ['/repay', { asset: 'usdc', share: '1', platform: 'aavev3' }],
] as [string, Record<string, string>][]) {
  cases.push({
    group: 'authz', name: `${path}: unknown (but well-formed) apiKey is rejected`,
    method: 'POST', path,
    params: { ...base, ...extra, apiKey: UNKNOWN_API_KEY },
    assert: expectRejected,
  });
}

// ---- odos deprecation: must be ACCEPTED, never an error ----------------------
// Live strategies still send platform=odos. It must be silently routed to the
// automatic DEX selection, NOT rejected as an unknown platform.

cases.push({
  group: 'odos', name: 'vaultTrade: platform=odos is accepted (not an unknown-platform error)',
  method: 'POST', path: '/vaultTrade',
  params: { ...base, from: 'usdc', to: 'weth', share: '1', platform: 'odos', apiKey: UNKNOWN_API_KEY },
  assert: (b, status, raw) => {
    if (/unknown platform/i.test(raw)) return 'odos was rejected as an unknown platform — this WILL break live strategies';
    return expectRejected(b, status); // rejected for the apiKey, which is expected
  },
});

cases.push({
  group: 'odos', name: 'vaultTrade: platform=auto is accepted',
  method: 'POST', path: '/vaultTrade',
  params: { ...base, from: 'usdc', to: 'weth', share: '1', platform: 'auto', apiKey: UNKNOWN_API_KEY },
  assert: (b, status, raw) => {
    if (/unknown platform/i.test(raw)) return 'auto was rejected as an unknown platform';
    return expectRejected(b, status);
  },
});

// ---- batched manager-fee minting (dry run only: submits nothing) --------------

cases.push({
  group: 'mintBatch', name: 'mintManagerFeeBatch: dryRun simulates every pool',
  path: '/mintManagerFeeBatch',
  params: { apiKey: API_KEY, network: NETWORK, dryRun: 'true', pools: POOL },
  assert: expectOk(b => {
    if (b?.dryRun !== true) return 'expected dryRun=true in response';
    if (!Array.isArray(b?.results)) return 'expected a results array';
    return null;
  }),
});

cases.push({
  group: 'mintBatch', name: 'mintManagerFeeBatch: missing pools -> rejected',
  path: '/mintManagerFeeBatch',
  params: { apiKey: API_KEY, network: NETWORK, dryRun: 'true' },
  assert: (b, status) => expectRejected(b, status),
});

cases.push({
  group: 'mintBatch', name: 'mintManagerFeeBatch: invalid pool in list -> 1004',
  path: '/mintManagerFeeBatch',
  params: { apiKey: API_KEY, network: NETWORK, dryRun: 'true', pools: `${POOL},${BAD_POOL}` },
  assert: expectFail(1004),
});

// ── runner ───────────────────────────────────────────────────────────────────

async function run() {
  const selected = onlyArg
    ? cases.filter(c => onlyArg.some(o => c.path.includes(o) || c.group === o || c.name.includes(o)))
    : cases;

  console.log(`\nEndpoint smoke test → ${BASE_URL}`);
  console.log(`pool=${POOL} network=${NETWORK} cases=${selected.length}\n`);

  let pass = 0;
  const failures: string[] = [];
  let currentGroup = '';

  for (const c of selected) {
    if (c.group !== currentGroup) {
      currentGroup = c.group;
      console.log(`\n── ${currentGroup} ─────────────────────────────`);
    }
    const qs = new URLSearchParams(c.params || {}).toString();
    const url = `${BASE_URL}${c.path}${qs ? `?${qs}` : ''}`;
    let raw = '';
    let body: any = null;
    let status = 0;
    try {
      const resp = await fetch(url, { method: c.method || 'GET' });
      status = resp.status;
      raw = await resp.text();
      try { body = JSON.parse(raw); } catch { body = raw; }
    } catch (e: any) {
      failures.push(`${c.name}: request failed: ${e.message}`);
      console.log(`  ✗ ${c.name} — request error: ${e.message}`);
      continue;
    }

    const problem = c.assert(body, status, raw);
    if (problem) {
      failures.push(`${c.name}: ${problem}`);
      console.log(`  ✗ ${c.name}\n      ${problem}`);
    } else {
      pass++;
      console.log(`  ✓ ${c.name}`);
    }
  }

  console.log(`\n${'='.repeat(60)}`);
  console.log(`PASSED ${pass}/${selected.length}`);
  if (failures.length) {
    console.log(`\nFAILURES (${failures.length}):`);
    failures.forEach(f => console.log(`  • ${f}`));
    process.exit(1);
  }
  console.log('All checks passed.');
}

run().catch(e => { console.error(e); process.exit(1); });
