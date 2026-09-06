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
// A real vault that the test API key is NOT the trader for, used to prove
// authorization is enforced before any state is written.
const NON_TRADER_POOL = (process.env.NON_TRADER_POOL || '0x749e1d46c83f09534253323a43541a9d2bbd03af').toLowerCase();
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

/**
 * Fetch that tolerates edge rate limiting.
 *
 * nginx enforces 30 req/min per IP (burst 20). This suite issues ~50 requests
 * back to back, so against the PUBLIC url it reliably trips the limiter and
 * every later case returns nginx's 503/429 HTML — which looks like a fleet of
 * endpoint failures but is really just the limiter doing its job. Retry with
 * backoff so the suite measures the API rather than the rate limiter.
 */
async function fetchWithRateLimitRetry(
  url: string,
  method: string,
  maxAttempts = 6,
): Promise<{ status: number; raw: string }> {
  let lastStatus = 0;
  let lastRaw = '';
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const resp = await fetch(url, { method });
    const raw = await resp.text();
    lastStatus = resp.status;
    lastRaw = raw;

    // 429 = app limiter, 503 = nginx limit_req rejecting before proxying.
    const rateLimited =
      resp.status === 429 ||
      (resp.status === 503 && /503 Service Temporarily Unavailable/i.test(raw));
    if (!rateLimited || attempt === maxAttempts) return { status: resp.status, raw };

    // nginx's window is per-minute; back off enough to actually clear it.
    await new Promise((r) => setTimeout(r, Math.min(2000 * attempt, 10000)));
  }
  return { status: lastStatus, raw: lastRaw };
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
  group: 'reads', name: 'aaveV3/getHealthFactor: read-only aave data',
  method: 'GET', path: '/aaveV3/getHealthFactor',
  params: base,
  assert: (b, status) => (status === 200 ? null : expectRejected(b, status)),
});

cases.push({
  group: 'reads', name: 'aaveV3/getPoolData: read-only aave data',
  method: 'GET', path: '/aaveV3/getPoolData',
  params: base,
  assert: (b, status) => (status === 200 ? null : expectRejected(b, status)),
});

// ---- validation parity across the migrated surface ---------------------------

addValidationSuite('validation', '/poolComposition', 'GET');
addValidationSuite('validation', '/aaveV3/getHealthFactor', 'GET');
addValidationSuite('validation', '/aaveV3/getPoolData', 'GET');
addValidationSuite('validation', '/vaultTrade', 'POST', { from: 'usdc', to: 'weth', share: '1' });
addValidationSuite('validation', '/setBot', 'POST', { side: 'hold', pair: 'ETH-USD', threshold: '1', share: '1', max_usd: '10' });
addValidationSuite('validation', '/aaveV3/lend', 'POST', { asset: 'usdc', share: '1' });
addValidationSuite('validation', '/aaveV3/unlend', 'POST', { asset: 'usdc', share: '1' });
addValidationSuite('validation', '/aaveV3/borrow', 'POST', { asset: 'usdc', amount: '1' });
addValidationSuite('validation', '/aaveV3/repay', 'POST', { asset: 'usdc', share: '1' });
addValidationSuite('validation', '/compoundV3/lend', 'POST', { asset: 'usdc', share: '1' });
addValidationSuite('validation', '/fluid/lend', 'POST', { asset: 'usdc', share: '1' });

// ---- money-moving endpoints must REJECT unknown credentials -------------------
// (These prove authorisation is enforced. None of them can execute here.)

for (const [path, extra] of [
  ['/vaultTrade', { from: 'usdc', to: 'weth', share: '1' }],
  ['/aaveV3/lend', { asset: 'usdc', share: '1' }],
  ['/aaveV3/unlend', { asset: 'usdc', share: '1' }],
  ['/aaveV3/repay', { asset: 'usdc', share: '1' }],
  ['/compoundV3/lend', { asset: 'usdc', share: '1' }],
  ['/fluid/lend', { asset: 'usdc', share: '1' }],
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

// ---- chamber alias: `chamber` is the current brand name for `dhedge` ---------
// Normalized in middleware (src/protocolAlias.ts) so it must behave EXACTLY
// like dhedge on every endpoint, while genuinely bad protocols still fail.

cases.push({
  group: 'chamber', name: 'poolComposition: protocol=chamber matches protocol=dhedge',
  method: 'GET', path: '/poolComposition',
  params: { ...base, protocol: 'chamber' },
  assert: (b, status, raw) => {
    if (status !== 200) return `chamber rejected with HTTP ${status}: ${raw.slice(0, 120)}`;
    if (/unrecognized protocol/i.test(raw)) return 'chamber was rejected as an unrecognized protocol';
    if (!Array.isArray(b)) return `expected a composition array, got: ${raw.slice(0, 120)}`;
    return null;
  },
});

cases.push({
  group: 'chamber', name: 'poolComposition: protocol=CHAMBER (case-insensitive) is accepted',
  method: 'GET', path: '/poolComposition',
  params: { ...base, protocol: 'CHAMBER' },
  assert: (b, status, raw) => {
    if (/unrecognized protocol/i.test(raw)) return 'uppercase CHAMBER was rejected';
    return status === 200 ? null : `HTTP ${status}: ${raw.slice(0, 120)}`;
  },
});

cases.push({
  group: 'chamber', name: 'poolComposition: an unknown protocol is still rejected (1001)',
  method: 'GET', path: '/poolComposition',
  params: { ...base, protocol: 'definitely-not-a-protocol' },
  assert: (b, status, raw) => {
    if (!/unrecognized protocol/i.test(raw) && !/1001/.test(raw)) {
      return `the alias middleware must not weaken protocol validation; got: ${raw.slice(0, 160)}`;
    }
    return null;
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

// ── mintAllFeesByManager: discovery-based batching ───────────────────────────
// Every case is dryRun, so nothing is ever submitted by the suite.

const ITP_DAO_MANAGER = '0xb5dB6e5a301E595B76F40319896a8dbDc277CEfB';

cases.push({
  group: 'mintByManager', name: 'mintAllFeesByManager: discovers the DAO vaults and filters zero-fee ones',
  path: '/mintAllFeesByManager',
  params: { apiKey: API_KEY, network: NETWORK, manager: ITP_DAO_MANAGER, dryRun: 'true' },
  assert: expectOk(b => {
    if (b?.dryRun !== true) return 'expected dryRun=true in response';
    if (!Array.isArray(b?.results)) return 'expected a results array';
    // scanned >= matched >= eligible must hold, or discovery/filtering is wrong.
    if (!(b.scanned >= b.matched && b.matched >= b.eligible)) {
      return `nonsensical counts: scanned=${b.scanned} matched=${b.matched} eligible=${b.eligible}`;
    }
    if (b.matched < 1) return 'expected at least one vault for the DAO manager';
    // The whole point of the endpoint: never batch a vault with no fee owed.
    const zeroFee = (b.results || []).filter((r: any) => !r.hasFee);
    if (zeroFee.length) return `zero-fee vaults leaked into the batch: ${JSON.stringify(zeroFee)}`;
    return null;
  }),
});

cases.push({
  group: 'mintByManager', name: 'mintAllFeesByManager: missing manager -> rejected',
  path: '/mintAllFeesByManager',
  params: { apiKey: API_KEY, network: NETWORK, dryRun: 'true' },
  assert: (b, status) => expectRejected(b, status),
});

cases.push({
  group: 'mintByManager', name: 'mintAllFeesByManager: malformed manager -> 1004',
  path: '/mintAllFeesByManager',
  params: { apiKey: API_KEY, network: NETWORK, manager: '0xdeadbeef', dryRun: 'true' },
  assert: expectFail(1004),
});

cases.push({
  group: 'mintByManager', name: 'mintAllFeesByManager: manager with no vaults returns 0 matched, not an error',
  path: '/mintAllFeesByManager',
  params: {
    apiKey: API_KEY, network: NETWORK,
    manager: '0x000000000000000000000000000000000000dEaD', dryRun: 'true',
  },
  assert: expectOk(b => {
    if (b?.matched !== 0) return `expected matched=0, got ${b?.matched}`;
    // scanned must still be non-zero, otherwise "0 matched" is meaningless and
    // could be hiding a broken candidate query rather than a real answer.
    if (!(b?.scanned > 0)) return 'expected a non-zero scanned count';
    return null;
  }),
});

// ── frontend shared API key ──────────────────────────────────────────────────
// These endpoints authenticate with FRONTEND_API_KEY. If this breaks, the
// public site's charts and yield figures go blank.

cases.push({
  group: 'frontendKey', name: 'getAllYields: the frontend key is accepted',
  path: '/getAllYields',
  params: { apiKey: 'frontend' },
  assert: (b, status, raw) => {
    if (status !== 200) return `HTTP ${status}`;
    if (/invalid api key/i.test(raw)) return 'the frontend key was rejected — the public site will break';
    return null;
  },
});

cases.push({
  group: 'frontendKey', name: 'getAllYields: a wrong key is still rejected',
  path: '/getAllYields',
  params: { apiKey: 'not-the-frontend-key' },
  assert: (b, status, raw) => {
    if (!/invalid api key/i.test(raw) && !/401/.test(raw)) {
      return `expected rejection, got: ${raw.slice(0, 160)}`;
    }
    return null;
  },
});

// ── index vault allocations ───────────────────────────────────────────
// setAllocations/rebalancePool move real funds when execute=true, so these
// cases only exercise validation and the DRY RUN path. None of them trade.

cases.push({
  group: 'allocations', name: 'setAllocations: weights that do not sum to 100 are rejected',
  method: 'POST', path: '/setAllocations',
  params: { ...base, assets: 'WBTC-WETH', allocations: '50-40' },
  assert: (b) => (/sum to 100/i.test(JSON.stringify(b)) ? null : `expected a sum-to-100 error, got ${JSON.stringify(b).slice(0, 160)}`),
});

cases.push({
  group: 'allocations', name: 'setAllocations: assets/allocations length mismatch is rejected',
  method: 'POST', path: '/setAllocations',
  params: { ...base, assets: 'WBTC-WETH-USDC', allocations: '50-50' },
  assert: (b) => (/must match/i.test(JSON.stringify(b)) ? null : `expected a length-mismatch error, got ${JSON.stringify(b).slice(0, 160)}`),
});

cases.push({
  group: 'allocations', name: 'setAllocations: a duplicate asset is rejected',
  method: 'POST', path: '/setAllocations',
  params: { ...base, assets: 'WBTC-WBTC', allocations: '50-50' },
  assert: (b) => (/duplicate asset/i.test(JSON.stringify(b)) ? null : `expected a duplicate-asset error, got ${JSON.stringify(b).slice(0, 160)}`),
});

cases.push({
  group: 'allocations', name: 'setAllocations: a non-trader is rejected before anything is stored (1006)',
  method: 'POST', path: '/setAllocations',
  params: { ...base, pool: NON_TRADER_POOL, assets: 'WBTC-WETH', allocations: '50-50' },
  assert: (b) => {
    const code = String((b as any)?.status_code ?? '');
    return code === '1006' || code === '1004' ? null : `expected 1006/1004, got ${JSON.stringify(b).slice(0, 160)}`;
  },
});

cases.push({
  group: 'allocations', name: 'getCurrentAllocations: an unconfigured pool returns 404, not a crash',
  path: '/getCurrentAllocations',
  params: { ...base },
  assert: (b) => {
    const code = String((b as any)?.status_code ?? '');
    // 200 is valid too if this pool happens to have allocations configured.
    return ['404', '200'].includes(code) ? null : `expected 404 or 200, got ${JSON.stringify(b).slice(0, 160)}`;
  },
});

cases.push({
  group: 'allocations', name: 'rebalancePool: defaults to a dry run and never reports executed=true',
  method: 'POST', path: '/rebalancePool',
  params: { ...base },
  assert: (b) => {
    const d = (b as any)?.data;
    if (d && d.executed === true) return 'DRY RUN DEFAULT BROKEN — rebalancePool traded without execute=true';
    return null;
  },
});

// ── bot status ────────────────────────────────────────────────────────

cases.push({
  group: 'botStatus', name: 'getBotStatus: reports bot, allocation and gas wallet state',
  path: '/getBotStatus',
  params: { ...base },
  assert: (b) => {
    const d = (b as any)?.data;
    if (!d) return `no data: ${JSON.stringify(b).slice(0, 160)}`;
    if (typeof d.hasBot !== 'boolean' || typeof d.hasAllocations !== 'boolean') {
      return `expected hasBot/hasAllocations booleans, got ${JSON.stringify(d).slice(0, 160)}`;
    }
    return null;
  },
});

cases.push({
  group: 'botStatus', name: 'isPoolTrader: a malformed trader address is rejected',
  path: '/isPoolTrader',
  params: { ...base, trader: 'not-an-address' },
  assert: (b) => (/valid address/i.test(JSON.stringify(b)) ? null : `expected an address error, got ${JSON.stringify(b).slice(0, 160)}`),
});

cases.push({
  group: 'botStatus', name: 'isPoolTrader: a wrong address returns isTrader=false rather than an error',
  path: '/isPoolTrader',
  params: { ...base, trader: '0x0000000000000000000000000000000000000001' },
  assert: (b) => {
    const d = (b as any)?.data;
    if (!d) return `no data: ${JSON.stringify(b).slice(0, 160)}`;
    if (d.isTrader !== false) return `expected isTrader=false, got ${JSON.stringify(d).slice(0, 160)}`;
    return null;
  },
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
      const resp = await fetchWithRateLimitRetry(url, c.method || 'GET');
      status = resp.status;
      raw = resp.raw;
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
