/**
 * requests/lend.ts — Node port of R gateway's lendHandler (port 8002,
 * src/api/api.R lines ~508-553), historically proxied via R gateway /lend ->
 * port 8002 /lend -> Express's own /lend (now renamed /lendRaw, see
 * requests/lending.ts).
 *
 * ***MONEY-MOVING*** — lends an asset into Aave v3 from a dHEDGE vault.
 * Ported with extra scrutiny; validation order mirrors R exactly.
 *
 * PARITY NOTES (lendHandler):
 *  1. protocol/pool/network/platform lower-cased.
 *  2. api_check(apiKey, protocol, pool, wallet=NULL, network) -- fail ->
 *     return check as-is.
 *  3. asset resolved via get_contract(asset, network) -- accepts either a
 *     0x address (passed through) or a symbol (DB lookup via coins/networks
 *     tables, same query as getContract.ts).
 *  4. share is REQUIRED (R's `amount` support is entirely commented out in
 *     lendHandler -- lines 523-528 -- so only share is used, replicated
 *     faithfully: `amount` param is accepted but ignored for API
 *     compatibility, matching R's actual current behavior even though this
 *     looks like a work-in-progress state in R). Must be numeric in (0,100]
 *     (fail -> status_code 1007), rounded to 2 decimals.
 *  5. Forwards to /lendRaw with the resolved asset contract + share.
 *  6. On success (200), R's lendHandler re-parses the JSON body and returns
 *     it as a plain list (never the raw httr response) -- replicated by
 *     simply forwarding /lendRaw's JSON body through.
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

// Port of R's get_contract(coin, network): pass through if already a 0x
// address, otherwise resolve via the coins/networks DB tables.
async function getContract(coin: string, network: string): Promise<string | null> {
  if (isValidEthereumAddress(coin)) return coin;
  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [coin.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].contract) : null;
  } catch {
    return null;
  }
}

/**
 * @openapi
 * /lend:
 *   post:
 *     summary: Lend an asset into Aave v3 from a dHEDGE vault (MONEY-MOVING)
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
 *         name: share
 *         required: true
 *         schema: { type: number }
 *       - in: query
 *         name: platform
 *         schema: { type: string, default: aave }
 *     responses:
 *       200:
 *         description: Lend executed.
 */
async function handleLend(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || '').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const platform = String(q.platform || '').toLowerCase();
  const asset = String(q.asset || '');
  const shareRaw = q.share === undefined ? undefined : String(q.share);

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

  // === lendHandler body ===
  const assetContract = await getContract(asset, network);
  if (!assetContract) {
    return res.json({ status: 'fail', status_code: 400, message: `Unable to resolve asset contract for '${asset}' on network '${network}'` });
  }

  if (shareRaw === undefined) {
    return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be numeric (0,100]' });
  }
  const shareNum = Number(shareRaw);
  if (!Number.isFinite(shareNum) || Number.isNaN(shareNum)) {
    return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be numeric (0,100]' });
  }
  if (shareNum <= 0 || shareNum > 100) {
    return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be in (0,100]' });
  }
  const share = Math.round(shareNum * 100) / 100;

  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('protocol', protocol);
  params.set('pool', pool);
  params.set('network', network);
  params.set('asset', assetContract);
  params.set('platform', platform);
  params.set('share', String(share));

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';

  try {
    const url = `${EXPRESS_BASE}lendRaw?${params.toString()}`;
    console.log(`lend -> ${url.replace(apiKey, maskedApi)}`);
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));

    const logMsg = `${resp.status === 200 ? 'success' : 'fail'} lend invoked apiKey: ${maskedApi} / pool: ${pool} / protocol: ${protocol} / network: ${network} / asset: ${asset} / share: ${share} / platform: ${platform} / response: ${JSON.stringify(data)}`;
    console.log(logMsg);

    if (resp.status === 200) {
      return res.json(data);
    }
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: lend — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing lend: ${e.message}` });
  }
}

router.post('/lend', handleLend);

export default router;
