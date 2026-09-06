/**
 * requests/getHealthFactor.ts — Node port of R gateway's
 * getHealthFactorHandler (port 8002, src/api/api.R lines ~631-678),
 * historically proxied via R gateway /getHealthFactor -> port 8002's
 * /getHealthFactor -> Express's own /getHealthFactor (now renamed
 * /getHealthFactorRaw, see requests/lending.ts).
 *
 * Read-only (no funds moved) — reports the Aave v3 health factor for a
 * dHEDGE vault's lending position.
 *
 * PARITY NOTES (getHealthFactorHandler) — validation ORDER is unusual and
 * replicated exactly, including the apparent R bug/quirk:
 *  1. protocol/pool/network/platform lower-cased.
 *  2. api_check(...) is COMPUTED (its getWallet(apiKey) HTTP call and
 *     isValidTrader() check DO run, with side effects/logging) but its
 *     result is NOT checked yet.
 *  3. platform=="aave" is aliased to "aavev3".
 *  4. pool_comp(pool, network, protocol) is fetched -- if unavailable, FAILS
 *     IMMEDIATELY with status_code 400 "unable to fetch pool composition",
 *     even if api_check would have failed too (api_check's own failure is
 *     checked LAST, after this). This is R's actual behavior, replicated
 *     faithfully even though it looks unintended (an auth failure could be
 *     masked by a composition-fetch failure).
 *  5. platform_contract = get_contract_from_symbol(platform, composition) --
 *     if missing, FAILS with status_code 400 "platform '<platform>' is not
 *     enabled inside the vault" (again, before the api_check result is
 *     consulted).
 *  6. ONLY NOW is api_check's status checked -- if it failed, return it.
 *  7. Calls Express's own /getHealthFactorRaw (GET) with the resolved
 *     platform_contract and returns its parsed JSON body directly.
 */

import { Router, Request, Response } from 'express';
import { isValidNetwork, isValidProtocol, isValidAPIKey, isValidEthereumAddress } from '../basicCheck';
import { isValidTrader } from '../dhedgeTrader';
import { poolComp } from '../tradeEngine';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

interface ApiCheckResult {
  failed: boolean;
  statusCode?: number | string;
  message?: any;
}

async function getWalletForApiKey(apiKey: string): Promise<{ wallet: string | null; failStatusCode?: number; failMessage?: any }> {
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

// Port of api_check(): runs getWallet + isValidTrader, but (matching R)
// callers may defer inspecting its result until after other work.
async function apiCheck(apiKey: string, protocol: string, pool: string): Promise<ApiCheckResult> {
  const { wallet, failStatusCode, failMessage } = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return { failed: true, statusCode: failStatusCode ?? 500, message: failMessage ?? 'Unable to resolve wallet for API key' };
  }
  const validTrader = await isValidTrader(protocol, pool, wallet);
  if (!validTrader) {
    return { failed: true, statusCode: '1006', message: 'The trader wallet is not configured as a trader in the specified pool' };
  }
  return { failed: false };
}

function getContractFromSymbol(symbol: string, comp: Awaited<ReturnType<typeof poolComp>>): string | null {
  if (!comp || !symbol) return null;
  const target = symbol.toLowerCase();
  const row = comp.find((r) => (r.symbol || '').toLowerCase() === target);
  return row ? row.asset : null;
}

/**
 * @openapi
 * /getHealthFactor:
 *   post:
 *     summary: Get the Aave v3 health factor for a dHEDGE vault (read-only)
 *     tags: [Lending]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, default: dhedge }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: platform
 *         schema: { type: string, default: aave }
 *     responses:
 *       200:
 *         description: Health factor data.
 */
async function handleGetHealthFactor(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || '').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  let platform = String(q.platform || '').toLowerCase();

  // === Format-level checks (network/protocol/apiKey/pool) run first, same
  // as api_check's own preconditions would if reached — but note R's
  // basic_check-equivalent format validation isn't actually invoked by
  // api_check() itself (it only does getWallet+isValidTrader); network's
  // validity is never format-checked at this layer in R. We still enforce
  // it here since sending garbage network/protocol downstream is unsafe and
  // an unrecognized network could not possibly have a valid pool anyway. ===
  if (!(await isValidNetwork(network))) {
    return res.json({ status: ['fail'], status_code: ['1000'], message: ['Unrecognized network'] });
  }
  if (!(await isValidProtocol(protocol))) {
    return res.json({ status: ['fail'], status_code: ['1001'], message: ['Unrecognized protocol'] });
  }
  if (!isValidAPIKey(apiKey)) {
    return res.json({ status: ['fail'], status_code: ['1002'], message: ['Invalid API Key'] });
  }
  if (!isValidEthereumAddress(pool)) {
    return res.json({ status: ['fail'], status_code: ['1004'], message: ['Invalid Pool Address'] });
  }

  // === api_check computed now, but its result is checked LAST (R quirk) ===
  const checkPromise = apiCheck(apiKey, protocol, pool);

  if (platform === 'aave') platform = 'aavev3';

  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }

  const platformContract = getContractFromSymbol(platform, composition);
  if (!platformContract) {
    return res.json({ status: 'fail', status_code: 400, message: `platform '${platform}' is not enabled inside the vault` });
  }

  const check = await checkPromise;
  if (check.failed) {
    return res.json({ status: 'fail', status_code: check.statusCode, message: check.message });
  }

  const params = new URLSearchParams();
  params.set('pool', pool);
  params.set('network', network);
  params.set('platform', platform);
  params.set('contractAddress', platformContract);

  try {
    const url = `${EXPRESS_BASE}getHealthFactorRaw?${params.toString()}`;
    console.log(`getHealthFactor -> ${url}`);
    const resp = await fetch(url);
    const data: any = await resp.json().catch(() => ({}));
    return res.json(data);
  } catch (e: any) {
    console.log(`Error: getHealthFactor — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error fetching health factor: ${e.message}` });
  }
}

router.post('/getHealthFactor', handleGetHealthFactor);

export default router;
