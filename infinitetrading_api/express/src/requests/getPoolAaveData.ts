/**
 * requests/getPoolAaveData.ts — Node port of R gateway's
 * getPoolAaveDataHandler (port 8002, src/api/api.R lines ~682-723),
 * historically proxied via R gateway /getPoolAaveData -> port 8002's
 * /getPoolAaveData -> Express's own /getPoolAaveData (now renamed
 * /getPoolAaveDataRaw, see requests/lending.ts).
 *
 * Read-only (no funds moved) — reports full Aave v3 account data for a
 * dHEDGE vault (health factor, total collateral, total debt, borrowing
 * power).
 *
 * PARITY NOTES (getPoolAaveDataHandler) — same "compute api_check but check
 * it last" quirk as getHealthFactorHandler, replicated faithfully:
 *  1. protocol/pool/network lower-cased; platform hardcoded to "AAVEV3"
 *     (only used for the platform-not-enabled error message text).
 *  2. api_check(...) computed but not checked yet.
 *  3. pool_comp(pool, network, protocol) fetched -- if unavailable, FAILS
 *     IMMEDIATELY with status_code 400 "unable to fetch pool composition"
 *     (before api_check's result is consulted).
 *  4. platform_contract = get_contract_from_symbol("AAVEV3", composition) --
 *     if missing, FAILS with status_code 400 "platform 'AAVEV3' is not
 *     enabled inside the vault" (again before api_check is consulted).
 *  5. ONLY NOW is api_check's status checked -- if it failed, return it.
 *  6. Calls Express's own /getPoolAaveDataRaw (GET) with the resolved
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
 * /getPoolAaveData:
 *   post:
 *     summary: Get full Aave v3 account data for a dHEDGE vault (read-only)
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
 *     responses:
 *       200:
 *         description: Aave v3 pool data.
 */
async function handleGetPoolAaveData(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || '').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const platform = 'AAVEV3';

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

  // === api_check computed now, checked LAST (R quirk, replicated) ===
  const checkPromise = apiCheck(apiKey, protocol, pool);

  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }

  const platformContract = getContractFromSymbol('AAVEV3', composition);
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
  params.set('contractAddress', platformContract);

  try {
    const url = `${EXPRESS_BASE}getPoolAaveDataRaw?${params.toString()}`;
    console.log(`getPoolAaveData -> ${url}`);
    const resp = await fetch(url);
    const data: any = await resp.json().catch(() => ({}));
    return res.json(data);
  } catch (e: any) {
    console.log(`Error: getPoolAaveData — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error fetching pool Aave data: ${e.message}` });
  }
}

// Registered for BOTH GET and POST. R served this as POST only, but its
// siblings getBorrowed/getSupplied/getHealthFactor all accept GET, so the
// POST-only restriction was an inconsistency rather than a deliberate choice.
// Accepting GET on a read-only handler removes a foot-gun: callers that use
// the natural verb previously got an HTML 404, which is unparseable by the
// JSON clients that consume this.
router.get('/getPoolAaveData', handleGetPoolAaveData);
router.post('/getPoolAaveData', handleGetPoolAaveData);

export default router;
