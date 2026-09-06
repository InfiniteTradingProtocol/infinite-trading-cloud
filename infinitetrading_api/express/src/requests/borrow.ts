/**
 * requests/borrow.ts — Node port of R gateway's borrowHandler (port 8002,
 * src/api/api.R), proxied historically via R gateway's /borrow -> port 8002's
 * /borrow -> Express's own /borrow (now renamed /borrowRaw, see
 * requests/lending.ts).
 *
 * ***MONEY-MOVING*** — this endpoint borrows against a dHEDGE vault's Aave v3
 * collateral. Ported with extra scrutiny; validation order mirrors R exactly.
 *
 * PARITY NOTES (borrowHandler, api.R lines ~451-504):
 *  1. protocol/pool/network/platform lower-cased.
 *  2. api_check(apiKey, protocol, pool, wallet=NULL, network) ==
 *     getWallet(apiKey) then isValidTrader(protocol, pool, wallet) -- fail ->
 *     returns api_check's own status/status_code/message (wrapped in R
 *     wire-format 1-element arrays, matching vaultTrade.ts's toRWireFormat
 *     usage for the getWallet-failure branch, and a literal 1006 fail object
 *     for the isValidTrader failure branch).
 *  3. share is COMMENTED OUT in R's borrowHandler (dead code, lines 460-470) —
 *     NOT validated at all. Only `amount` is used. Replicated faithfully:
 *     share is accepted as a parameter (for API compatibility) but ignored.
 *  4. amount must be numeric, > 0 (fail -> error_code 1011 / 1009 respectively
 *     -- note R uses the field name `error_code` here, NOT `status_code`,
 *     which is an R inconsistency/typo kept faithfully -- these were "res"
 *     objects returned directly as the handler's return value, so the actual
 *     wire shape is `{status:"fail", error_code:.., message:..}` NOT
 *     `status_code`). amount is rounded to 2 decimals, then forwarded AS-IS
 *     (NOT decimal-scaled by asset decimals -- this mirrors R's actual
 *     behavior, an existing quirk in borrowHandler/borrowRaw's expectations
 *     that predates this migration; replicated faithfully, not fixed, since
 *     changing it would alter live financial behavior).
 *  5. Forwards to (now) Express's own /borrowRaw with resolved asset contract
 *     via get_contract(asset, network) DB lookup (same as lendHandler).
 *  6. On success, R's borrowHandler returns the raw httr response object
 *     (unparsed) when status 200 -- Express instead returns /borrowRaw's own
 *     JSON body directly (status/msg), which is the correct externally
 *     observable behavior once R's httr-response wrapping quirk is unwound.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { isValidNetwork, isValidProtocol, isValidAPIKey, isValidEthereumAddress } from '../basicCheck';
import { isValidTrader } from '../dhedgeTrader';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

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

async function getContractForSymbol(symbol: string, network: string): Promise<string | null> {
  if (isValidEthereumAddress(symbol)) return symbol;
  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [symbol.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].contract) : null;
  } catch {
    return null;
  }
}

/**
 * @openapi
 * /borrow:
 *   post:
 *     summary: Borrow an asset against a dHEDGE vault's Aave v3 collateral (MONEY-MOVING)
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
 *         name: asset
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: amount
 *         required: true
 *         schema: { type: number }
 *       - in: query
 *         name: platform
 *         schema: { type: string, default: aave }
 *     responses:
 *       200:
 *         description: Borrow executed.
 */
async function handleBorrow(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || '').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const platform = String(q.platform || '').toLowerCase();
  const asset = String(q.asset || '');
  const amountRaw = q.amount === undefined ? undefined : String(q.amount);

  // === api_check equivalent ===
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

  const { wallet, failStatusCode, failMessage } = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return res.json({ status: 'fail', status_code: failStatusCode ?? 500, message: failMessage ?? 'Unable to resolve wallet for API key' });
  }
  const validTrader = await isValidTrader(protocol, pool, wallet);
  if (!validTrader) {
    return res.json({ status: 'fail', status_code: '1006', message: 'The trader wallet is not configured as a trader in the specified pool' });
  }

  // === borrowHandler body ===
  const assetContract = await getContractForSymbol(asset, network);
  if (!assetContract) {
    return res.json({ status: 'fail', error_code: 1011, message: `Unable to resolve asset contract for '${asset}' on network '${network}'` });
  }

  if (amountRaw === undefined) {
    return res.json({ status: 'fail', error_code: 1009, message: 'The specified amount must be > 0' });
  }
  const amountNum = Number(amountRaw);
  if (!Number.isFinite(amountNum) || Number.isNaN(amountNum)) {
    return res.json({ status: 'fail', error_code: 1011, message: 'The specified amount parameter is not numeric' });
  }
  if (amountNum <= 0) {
    return res.json({ status: 'fail', error_code: 1009, message: 'The specified amount must be > 0' });
  }
  const amount = Math.round(amountNum * 100) / 100;

  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('protocol', protocol);
  params.set('pool', pool);
  params.set('network', network);
  params.set('asset', assetContract);
  params.set('platform', platform);
  params.set('amount', String(amount));

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';

  try {
    const url = `${EXPRESS_BASE}borrowRaw?${params.toString()}`;
    console.log(`borrow -> ${url.replace(apiKey, maskedApi)}`);
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));

    const logMsg = `${resp.status === 200 ? 'success' : 'fail'} borrow invoked apiKey: ${maskedApi} / pool: ${pool} / protocol: ${protocol} / network: ${network} / asset: ${asset} / amount: ${amount} / platform: ${platform} / response: ${JSON.stringify(data)}`;
    console.log(logMsg);

    if (resp.status === 200) {
      return res.json(data);
    }
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: borrow — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing borrow: ${e.message}` });
  }
}

router.post('/borrow', handleBorrow);

export default router;
