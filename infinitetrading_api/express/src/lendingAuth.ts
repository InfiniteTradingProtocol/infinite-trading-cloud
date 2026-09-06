/**
 * lendingAuth.ts — shared authorization and asset resolution for every
 * money-moving lending route.
 *
 * WHY THIS EXISTS
 * The lending surface grew two parallel families with different security:
 *
 *   /lend, /unlend, /borrow, /repay   — basic_check + getWallet(apiKey) +
 *                                        isValidTrader(pool, wallet), and
 *                                        resolved `asset` from a symbol.
 *   /aaveV3/*, /compoundV3/*, /fluid/* — basic_check ONLY. No trader check.
 *
 * The second family is internet-facing and moves funds, so anyone holding any
 * valid API key could act on a vault they are not a trader on. That was
 * inherited from the R gateway and faithfully ported; it is fixed here.
 *
 * Both families now run the SAME checks through requireLendingAuth(), so the
 * per-protocol routes are strictly no weaker than the top-level ones they
 * replace. Keep this as the single gate: adding a protocol router should mean
 * calling this, never re-implementing the chain.
 */

import { Request } from 'express';
import { dbQuery } from './db';
import {
  basicCheck,
  toRWireFormat,
  isValidEthereumAddress,
} from './basicCheck';
import { isValidTrader } from './dhedgeTrader';

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

export interface LendingAuthOk {
  ok: true;
  apiKey: string;
  protocol: string;
  pool: string;
  network: string;
  wallet: string;
}

export interface LendingAuthFail {
  ok: false;
  body: any;
}

export type LendingAuthResult = LendingAuthOk | LendingAuthFail;

/**
 * Resolves the gas wallet behind an API key via Express's own /getWallet.
 * Kept as an HTTP call rather than a direct DB read so that any future
 * revocation/expiry logic in that endpoint applies here automatically.
 */
async function getWalletForApiKey(
  apiKey: string
): Promise<{ wallet: string | null; failStatusCode?: number; failMessage?: any }> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}getWallet?apiKey=${encodeURIComponent(apiKey)}`);
    const data: any = await resp.json().catch(() => ({}));
    if (resp.status === 200) {
      return { wallet: data && data.msg ? String(data.msg) : null };
    }
    return { wallet: null, failStatusCode: resp.status, failMessage: data };
  } catch {
    return { wallet: null, failStatusCode: 500, failMessage: 'Unable to resolve wallet for API key' };
  }
}

/**
 * Full validation chain for a money-moving lending call.
 *
 * Order matches the top-level handlers exactly so status codes stay stable for
 * existing callers: 1000 network, 1001 protocol, 1002 apiKey, 1004 pool,
 * 1006 not-a-trader.
 */
export async function requireLendingAuth(req: Request): Promise<LendingAuthResult> {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return { ok: false, body: toRWireFormat(check) };

  const { wallet, failStatusCode, failMessage } = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return {
      ok: false,
      body: {
        status: 'fail',
        status_code: failStatusCode ?? 500,
        message: failMessage ?? 'Unable to resolve wallet for API key',
      },
    };
  }

  const validTrader = await isValidTrader(protocol, pool, wallet);
  if (!validTrader) {
    return {
      ok: false,
      body: {
        status: 'fail',
        status_code: '1006',
        message: 'The trader wallet is not configured as a trader in the specified pool',
      },
    };
  }

  return { ok: true, apiKey, protocol, pool, network, wallet };
}

/**
 * Resolves an asset that may be a symbol ("usdc") or a 0x address.
 *
 * The per-protocol routers used to require a raw address and reject symbols
 * with 1004. Accepting both keeps every live R strategy — which passes
 * symbols — working against these routes.
 */
export async function resolveAsset(coin: string, network: string): Promise<string | null> {
  if (isValidEthereumAddress(coin)) return coin.toLowerCase();
  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [coin.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].contract).toLowerCase() : null;
  } catch {
    return null;
  }
}

/** Standard failure body for an asset that resolves to nothing. */
export function assetResolutionFailure(asset: string, network: string) {
  return {
    status: 'fail',
    status_code: 400,
    message: `Unable to resolve asset contract for '${asset}' on network '${network}'`,
  };
}

/**
 * Resolves the on-chain contract for a platform symbol (e.g. "aavev3") from
 * the vault's own composition.
 *
 * Share-based withdrawals need the platform's aToken/market address to know
 * what "50% of the supplied position" refers to; amount-based ones do not.
 * Reading it from composition also enforces that the platform is actually
 * enabled inside the vault before any transaction is attempted.
 */
export function getContractFromSymbol(
  symbol: string,
  comp: Array<{ symbol?: string; asset: string }> | null | undefined
): string | null {
  if (!comp || !symbol) return null;
  const target = symbol.toLowerCase();
  const row = comp.find((r) => (r.symbol || '').toLowerCase() === target);
  return row ? row.asset : null;
}
