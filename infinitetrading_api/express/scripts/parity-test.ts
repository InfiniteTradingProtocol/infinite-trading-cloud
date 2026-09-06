/**
 * scripts/parity-test.ts — Compares the shadow Express service's responses
 * against the live R gateway for every endpoint being migrated, across a set
 * of real + edge-case inputs, and reports any mismatch.
 *
 * Usage:
 *   R_GATEWAY_URL=http://localhost:8003 SHADOW_URL=http://localhost:8010 \
 *     API_KEY=<a-real-uuid-token> npx ts-node scripts/parity-test.ts
 *
 * Add a new `TestCase` group whenever you port a new endpoint. Each case hits
 * both backends with identical query params and diffs the JSON body (and,
 * where relevant, HTTP status code / error shape).
 *
 * KNOWN-BROKEN BASELINE: getSymbol / getContract currently return a generic
 * 500 from the live R gateway due to a pre-existing bug (is_valid_protocol
 * called with a zero-length argument — see src/shadow/endpoints/getSymbol.ts
 * for details). For these two, we do NOT diff against R's (broken) output;
 * instead we assert the SHADOW service returns a sane, well-formed response
 * (parity-with-intent, not parity-with-bug). Flip `expectRGatewayBroken` to
 * false once the R bug is fixed, to switch back to strict diffing.
 */

// Uses the global `fetch` built into Node 18+ — no extra dependency needed.

const R_GATEWAY_URL = process.env.R_GATEWAY_URL || 'http://localhost:8003';
const SHADOW_URL = process.env.SHADOW_URL || 'http://localhost:8010';
const API_KEY = process.env.API_KEY || '';

interface TestCase {
  name: string;
  path: string;
  params: Record<string, string>;
  expectRGatewayBroken?: boolean; // true = R is known-broken; only sanity-check shadow
}

const cases: TestCase[] = [
  {
    name: 'getSymbol: known WETH/base contract',
    path: '/getSymbol',
    params: { contract: '0x4200000000000000000000000000000000000006', network: 'base', apiKey: API_KEY },
    expectRGatewayBroken: true,
  },
  {
    name: 'getSymbol: unknown contract -> null',
    path: '/getSymbol',
    params: { contract: '0x000000000000000000000000000000deadbeef', network: 'base', apiKey: API_KEY },
    expectRGatewayBroken: true,
  },
  {
    name: 'getSymbol: invalid network -> 1000 fail',
    path: '/getSymbol',
    params: { contract: '0x4200000000000000000000000000000000000006', network: 'notarealnetwork', apiKey: API_KEY },
    expectRGatewayBroken: false, // this one actually returns correctly today (validated before the buggy branch)
  },
  {
    name: 'getContract: known WETH/base symbol',
    path: '/getContract',
    params: { symbol: 'weth', network: 'base', apiKey: API_KEY },
    expectRGatewayBroken: true,
  },
  {
    name: 'getContract: unknown symbol -> null',
    path: '/getContract',
    params: { symbol: 'notarealsymbolxyz', network: 'base', apiKey: API_KEY },
    expectRGatewayBroken: true,
  },
  {
    name: 'getContract: invalid network -> 1000 fail',
    path: '/getContract',
    params: { symbol: 'weth', network: 'notarealnetwork', apiKey: API_KEY },
    expectRGatewayBroken: false,
  },
  {
    name: 'getTotalYield: known pool, frontend key',
    path: '/getTotalYield',
    params: { pool: '0x948720ff3f5f26f889b42e22ee8d1c23da5063a3', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getTotalYield: invalid pool address format',
    path: '/getTotalYield',
    params: { pool: 'notanaddress', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getTotalYield: wrong apiKey',
    path: '/getTotalYield',
    params: { pool: '0x948720ff3f5f26f889b42e22ee8d1c23da5063a3', apiKey: 'not-frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getEstimatedAnualYield: known pool, frontend key',
    path: '/getEstimatedAnualYield',
    params: { pool: '0x948720ff3f5f26f889b42e22ee8d1c23da5063a3', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getAllYields: frontend key',
    path: '/getAllYields',
    params: { apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getAllYields: wrong apiKey',
    path: '/getAllYields',
    params: { apiKey: 'not-frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getCandles: known exchange/pair/timeframe, frontend key',
    path: '/getCandles',
    params: { exchange: 'coinbase', pair: 'BTC-USD', timeframe: '6h', bars_back: '3', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getCandles: invalid pair format',
    path: '/getCandles',
    params: { exchange: 'coinbase', pair: 'BTCUSD', timeframe: '6h', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getCandles: invalid bars_back (too large)',
    path: '/getCandles',
    params: { exchange: 'coinbase', pair: 'BTC-USD', timeframe: '6h', bars_back: '5000', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getCandles: unknown table -> empty',
    path: '/getCandles',
    params: { exchange: 'coinbase', pair: 'NOPE-USD', timeframe: '6h', apiKey: 'frontend' },
    expectRGatewayBroken: false,
  },
  {
    name: 'getCandles: wrong apiKey',
    path: '/getCandles',
    params: { exchange: 'coinbase', pair: 'BTC-USD', timeframe: '6h', apiKey: 'not-frontend' },
    expectRGatewayBroken: false,
  },
];

function buildUrl(base: string, path: string, params: Record<string, string>): string {
  const qs = new URLSearchParams(params).toString();
  return `${base}${path}?${qs}`;
}

async function fetchJson(url: string): Promise<{ status: number; body: any }> {
  const resp = await fetch(url);
  const text = await resp.text();
  let body: any;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { status: resp.status, body };
}

function deepEqual(a: any, b: any): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

async function runCase(tc: TestCase): Promise<{ name: string; pass: boolean; detail: string }> {
  const rUrl = buildUrl(R_GATEWAY_URL, tc.path, tc.params);
  const sUrl = buildUrl(SHADOW_URL, tc.path, tc.params);

  const [rResult, sResult] = await Promise.all([
    fetchJson(rUrl).catch((e) => ({ status: -1, body: `fetch error: ${e.message}` })),
    fetchJson(sUrl).catch((e) => ({ status: -1, body: `fetch error: ${e.message}` })),
  ]);

  if (tc.expectRGatewayBroken) {
    // Don't compare to R; just assert shadow responded with a valid HTTP 200
    // and non-error-shaped body.
    const shadowOk = sResult.status === 200 && !(sResult.body && sResult.body.error);
    return {
      name: tc.name,
      pass: shadowOk,
      detail: shadowOk
        ? `shadow=${JSON.stringify(sResult.body)} (R known-broken, skipped diff: ${JSON.stringify(rResult.body)})`
        : `shadow FAILED: status=${sResult.status} body=${JSON.stringify(sResult.body)}`,
    };
  }

  const match = rResult.status === sResult.status && deepEqual(rResult.body, sResult.body);
  return {
    name: tc.name,
    pass: match,
    detail: match
      ? `MATCH: ${JSON.stringify(sResult.body)}`
      : `MISMATCH:\n  R      (${rResult.status}): ${JSON.stringify(rResult.body)}\n  SHADOW (${sResult.status}): ${JSON.stringify(sResult.body)}`,
  };
}

async function main() {
  if (!API_KEY) {
    console.error('ERROR: set API_KEY env var to a real UUID token from api_tokens before running.');
    process.exit(1);
  }

  console.log(`Comparing R gateway (${R_GATEWAY_URL}) vs shadow service (${SHADOW_URL})\n`);

  let failures = 0;
  for (const tc of cases) {
    const result = await runCase(tc);
    const icon = result.pass ? '✅' : '❌';
    console.log(`${icon} ${result.name}`);
    console.log(`   ${result.detail}\n`);
    if (!result.pass) failures++;
  }

  console.log(failures === 0 ? `All ${cases.length} parity checks passed.` : `${failures}/${cases.length} checks FAILED.`);
  process.exit(failures === 0 ? 0 : 1);
}

main();
