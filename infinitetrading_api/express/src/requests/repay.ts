/**
 * requests/repay.ts — Node port of R gateway's repayHandler (port 8002,
 * src/api/api.R lines ~395-447), historically proxied via R gateway /repay ->
 * port 8002 /repay -> Express's own /repay (now renamed /repayRaw, see
 * requests/lending.ts).
 *
 * ***MONEY-MOVING*** — repays borrowed assets against a dHEDGE vault's Aave v3
 * debt. Ported with extra scrutiny; validation order mirrors R exactly.
 *
 * PARITY NOTES (repayHandler):
 *  1. protocol/pool/network/platform lower-cased.
 *  2. api_check(apiKey, protocol, pool, wallet=NULL, network) -- fail ->
 *     return check as-is.
 *  3. asset is forwarded RAW (NOT resolved via get_contract in R's
 *     repayHandler -- unlike lendHandler/unlendHandler/borrowHandler, R's
 *     repayHandler builds the url with `&asset=", asset` directly, no
 *     get_contract() call. Replicated faithfully.)
 *  4. share (if given): must be numeric in [1,100] (fail -> status_code 1007).
 *     If valid, rounded to whole number and appended to URL.
 *  5. amount (if given, independently of share -- R does NOT make these
 *     mutually exclusive for repay, both may be appended if both are valid):
 *     must be numeric (fail -> error_code 1011) and > 0 (fail -> error_code
 *     1009). Rounded to 2 decimals.
 *  6. Forwards to /repayRaw with whichever of share/amount validated.
 */

import { Router, Request, Response } from 'express';
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

/**
 * @openapi
 * /repay:
 *   post:
 *     summary: Repay borrowed assets to a dHEDGE vault's Aave v3 position (MONEY-MOVING)
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
 *         schema: { type: number }
 *       - in: query
 *         name: amount
 *         schema: { type: number }
 *       - in: query
 *         name: platform
 *         schema: { type: string, default: aave }
 *     responses:
 *       200:
 *         description: Repay executed.
 */
async function handleRepay(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || '').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const platform = String(q.platform || '').toLowerCase();
  const asset = String(q.asset || '');
  const shareRaw = q.share === undefined ? undefined : String(q.share);
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

  // === repayHandler body ===
  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('protocol', protocol);
  params.set('pool', pool);
  params.set('network', network);
  params.set('asset', asset);
  params.set('platform', platform);

  let share: number | undefined;
  if (shareRaw !== undefined) {
    const shareNum = Number(shareRaw);
    if (!Number.isFinite(shareNum) || Number.isNaN(shareNum)) {
      return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be numeric [1,100]' });
    }
    if (shareNum < 1 || shareNum > 100) {
      return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be in [1,100]' });
    }
    share = Math.round(shareNum);
    params.set('share', String(share));
  }

  let amount: number | undefined;
  if (amountRaw !== undefined) {
    const amountNum = Number(amountRaw);
    if (!Number.isFinite(amountNum) || Number.isNaN(amountNum)) {
      return res.json({ status: 'fail', error_code: 1011, message: 'The specified amount parameter is not numeric' });
    }
    if (amountNum <= 0) {
      return res.json({ status: 'fail', error_code: 1009, message: 'The specified amount must be > 0' });
    }
    amount = Math.round(amountNum * 100) / 100;
    params.set('amount', String(amount));
  }

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';

  try {
    const url = `${EXPRESS_BASE}repayRaw?${params.toString()}`;
    console.log(`repay -> ${url.replace(apiKey, maskedApi)}`);
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));

    const logMsg = `${resp.status === 200 ? 'success' : 'fail'} repay invoked apiKey: ${maskedApi} / pool: ${pool} / protocol: ${protocol} / network: ${network} / asset: ${asset} / share: ${share ?? 'NA'} / amount: ${amount ?? 'NA'} / platform: ${platform} / response: ${JSON.stringify(data)}`;
    console.log(logMsg);

    if (resp.status === 200) {
      return res.json(data);
    }
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: repay — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing repay: ${e.message}` });
  }
}

router.post('/repay', handleRepay);

export default router;
