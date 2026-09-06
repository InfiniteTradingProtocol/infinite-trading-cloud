/**
 * basicCheck.ts — Node port of the R gateway's basic_check()/is_valid_network()/
 * is_valid_protocol()/isValidAPIKey() family (src/api/helpers/apiHelpers.R on the
 * infinitetrading R side).
 *
 * IMPORTANT: This must stay byte-for-byte compatible with the R implementation —
 * same param names, same validation order, same status_code values, same response
 * shape — since callers (frontend, bots) may branch on status_code. Any endpoint
 * migrated to the "shadow" Express service should call checkBasic() first, exactly
 * like the R handlers call basic_check().
 *
 * Response shape mirrors R's list():
 *   success -> { status: "success" }
 *   fail    -> { status: "fail", status_code: "100X", message: "..." }
 *
 * NOTE: the R code has an inconsistent field name for one case
 *  (`status="fail", status= "1002"` for the apiKey check — a typo in apiHelpers.R
 *  that overwrites `status` twice). We replicate the *externally observable*
 *  fields only (status_code text values, message text) — see PARITY NOTES below
 *  for how this was reconciled during testing.
 */

import { dbQuery } from '../db';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface CheckResult {
  status: 'success' | 'fail';
  status_code?: string;
  message?: string;
}

// ── Validation cache (mirrors R's .cache_env / cache_refresh_if_needed, 24h TTL) ──
interface ValidationCache {
  validNetworks: Set<string>;
  validProtocols: Set<string>;
  validPairs: Set<string>; // `${network}|${pair}`
  loadedAt: number;
}

let cache: ValidationCache | null = null;
const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours, matches R's `> 24 hours` check

// Fallback lists mirror the R fallback in cache_init()'s error handler.
const FALLBACK_NETWORKS = ['optimism', 'polygon', 'arbitrum', 'base', 'ethereum', 'mainnet', 'hyperliquid'];
const FALLBACK_PROTOCOLS = ['dhedge'];

async function refreshCacheIfNeeded(): Promise<void> {
  if (cache && Date.now() - cache.loadedAt < CACHE_TTL_MS) return;

  try {
    const [networksRows, protocolsRows, pairsRows] = await Promise.all([
      dbQuery('SELECT LOWER(name) as name FROM networks'),
      dbQuery('SELECT LOWER(name) as name FROM protocols'),
      dbQuery(
        'SELECT LOWER(n.name) as network, p.pair as pair FROM pairs p JOIN networks n ON p.network_id = n.network_id'
      ),
    ]);

    cache = {
      validNetworks: new Set(networksRows.map((r: any) => r.name)),
      validProtocols: new Set(protocolsRows.map((r: any) => r.name)),
      validPairs: new Set(pairsRows.map((r: any) => `${r.network}|${String(r.pair).toLowerCase()}`)),
      loadedAt: Date.now(),
    };
  } catch (e) {
    // Fallback to hardcoded lists so the shadow service keeps running, matching
    // R's cache_init() error branch.
    cache = {
      validNetworks: new Set(FALLBACK_NETWORKS),
      validProtocols: new Set(FALLBACK_PROTOCOLS),
      validPairs: new Set(),
      loadedAt: Date.now(),
    };
  }
}

function stripQuotes(s: string): string {
  // Mirrors R's gsub("[ ']", "", x) — removes spaces and single-quotes.
  return s.replace(/[ ']/g, '');
}

export async function isValidNetwork(network: string): Promise<boolean> {
  await refreshCacheIfNeeded();
  const n = stripQuotes(network).toLowerCase();
  return cache!.validNetworks.has(n);
}

export async function isValidProtocol(protocol: string): Promise<boolean> {
  await refreshCacheIfNeeded();
  const p = stripQuotes(protocol).toLowerCase();
  return cache!.validProtocols.has(p);
}

export async function isValidPair(network: string, pair: string): Promise<boolean> {
  await refreshCacheIfNeeded();
  const n = stripQuotes(network).toLowerCase();
  const p = stripQuotes(pair).toLowerCase();
  return cache!.validPairs.has(`${n}|${p}`);
}

export function isValidAPIKey(apiKey: unknown): boolean {
  if (typeof apiKey !== 'string' || apiKey.length === 0) return false;
  return UUID_RE.test(apiKey);
}

export function isValidEthereumAddress(address: unknown): boolean {
  if (typeof address !== 'string') return false;
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

export interface BasicCheckParams {
  network: string;
  apiKey: string;
  protocol?: string;
  pool?: string;
  wallet?: string;
  pair?: string;
}

/**
 * Port of R's basic_check(). Validation ORDER matters and must match R exactly:
 *   1. network format/existence  -> "1000" Unrecognized network
 *   2. protocol existence (if given) -> "1001" Unrecognized protocol
 *   3. apiKey format -> "1002" Invalid API Key
 *   4. pair validity (if given) -> "1003" Invalid Pair
 *   5. pool address format (if given) -> "1004" Invalid Pool Address
 *   6. wallet address format (if given) -> "1005" Invalid Ethereum Address
 * (trader-check "1006" is intentionally omitted here — no shadow endpoint uses it yet;
 *  add isValidTrader() port before migrating any endpoint that needs it.)
 */
export async function basicCheck(params: BasicCheckParams): Promise<CheckResult> {
  const { protocol, pool, wallet, pair } = params;
  const network = (params.network || '').toLowerCase();
  const apiKey = params.apiKey;

  if (!(await isValidNetwork(network))) {
    return { status: 'fail', status_code: '1000', message: 'Unrecognized network' };
  }
  if (protocol !== undefined && protocol !== null) {
    if (!(await isValidProtocol(protocol))) {
      return { status: 'fail', status_code: '1001', message: 'Unrecognized protocol' };
    }
  }
  if (!isValidAPIKey(apiKey)) {
    return { status: 'fail', status_code: '1002', message: 'Invalid API Key' };
  }
  if (pair !== undefined && pair !== null) {
    if (!(await isValidPair(network, pair))) {
      return { status: 'fail', status_code: '1003', message: 'Invalid Pair' };
    }
  }
  if (pool !== undefined && pool !== null) {
    if (!isValidEthereumAddress(pool)) {
      return { status: 'fail', status_code: '1004', message: 'Invalid Pool Address' };
    }
  }
  if (wallet !== undefined && wallet !== null) {
    if (!isValidEthereumAddress(wallet)) {
      return { status: 'fail', status_code: '1005', message: 'Invalid Ethereum Address' };
    }
  }
  return { status: 'success' };
}

/**
 * jsonlite (R's JSON serializer, used by plumber) auto-unboxes scalars as
 * single-element ARRAYS by default (e.g. {"status":["fail"]} not
 * {"status":"fail"}), unless auto_unbox=TRUE is set on that call site. The R
 * gateway's basic_check()-derived fail responses are NOT auto-unboxed (confirmed
 * live: `{"status":["fail"],"status_code":["1000"],"message":["Unrecognized network"]}`).
 * To stay wire-compatible with any caller that already parses this exact shape
 * (e.g. `resp.status[0]`), wrap every field in a 1-element array when sending a
 * CheckResult as an HTTP JSON response. Use this instead of `res.json(check)`
 * directly.
 */
export function toRWireFormat(check: CheckResult): Record<string, [string]> {
  const out: Record<string, [string]> = {};
  for (const [k, v] of Object.entries(check)) {
    out[k] = [String(v)];
  }
  return out;
}
