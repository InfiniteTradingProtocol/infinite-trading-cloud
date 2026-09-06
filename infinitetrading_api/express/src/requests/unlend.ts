/**
 * requests/unlend.ts — Node port of R gateway's unlendHandler (port 8002,
 * src/api/api.R lines ~557-627), historically proxied via R gateway /unlend
 * -> port 8002 /unlend -> Express's own /unlend (now renamed /unlendRaw, see
 * requests/lending.ts).
 *
 * ***MONEY-MOVING*** — withdraws (unlends) an asset from Aave v3 within a
 * dHEDGE vault. Ported with extra scrutiny; validation order mirrors R
 * exactly.
 *
 * PARITY NOTES (unlendHandler):
 *  1. protocol/pool/network/platform lower-cased.
 *  2. api_check(apiKey, protocol, pool, wallet=NULL, network) -- fail ->
 *     return check as-is.
 *  3. asset resolved via get_contract(asset, network) (same as lendHandler).
 *  4. If `share` is given (even if `amount` is ALSO given -- R's `if
 *     (!is.null(share))` branch takes priority, `amount` branch is only
 *     reached `else if`): fetch pool composition via pool_comp(), resolve
 *     platform_contract = get_contract_from_symbol(platform, composition)
 *     (fail if pool composition unavailable -> status_code 400, or if
 *     platform not enabled in vault -> status_code 400). Then share must be
 *     numeric in (0,100] (fail -> status_code 1007), forwarded along with
 *     the resolved contractAddress.
 *  5. Else if `amount` is given: must be numeric (fail -> status_code 1011)
 *     and > 0 (fail -> status_code 1009). Rounded to 2 decimals. No
 *     contractAddress resolution needed in this branch (matches R: platform
 *     _contract stays NULL when share is NULL).
 *  6. Else (neither share nor amount given): fail -> status_code 400 "No
 *     share or amount parameter specified".
 *  7. Forwards to /unlendRaw with whichever branch validated.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { isValidNetwork, isValidProtocol, isValidAPIKey, isValidEthereumAddress } from '../basicCheck';
import { isValidTrader } from '../dhedgeTrader';
import { poolComp } from '../tradeEngine';

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

// Port of R's get_contract_from_symbol(symbol, comp): finds the composition
// row whose `symbol` field matches (case-insensitively) and returns its
// `asset` (contract address) field.
function getContractFromSymbol(symbol: string, comp: Awaited<ReturnType<typeof poolComp>>): string | null {
  if (!comp || !symbol) return null;
  const target = symbol.toLowerCase();
  const row = comp.find((r) => (r.symbol || '').toLowerCase() === target);
  return row ? row.asset : null;
}

/**
 * @openapi
 * /unlend:
 *   post:
 *     summary: Withdraw (unlend) an asset from Aave v3 within a dHEDGE vault (MONEY-MOVING)
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
 *         description: Unlend executed.
 */
async function handleUnlend(req: Request, res: Response) {
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

  // === unlendHandler body ===
  const assetContract = await getContract(asset, network);
  if (!assetContract) {
    return res.json({ status: 'fail', status_code: 400, message: `Unable to resolve asset contract for '${asset}' on network '${network}'` });
  }

  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('protocol', protocol);
  params.set('pool', pool);
  params.set('network', network);
  params.set('asset', assetContract);
  params.set('platform', platform);

  let share: number | undefined;
  let amount: number | undefined;

  if (shareRaw !== undefined) {
    // Resolve platform contract from pool composition (share-based unlend only).
    const composition = await poolComp(pool, network, protocol, apiKey);
    if (!composition || composition.length === 0) {
      return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
    }
    const platformContract = getContractFromSymbol(platform, composition);
    if (!platformContract) {
      return res.json({ status: 'fail', status_code: 400, message: `platform '${platform}' is not enabled inside the vault` });
    }
    params.set('contractAddress', platformContract);

    const shareNum = Number(shareRaw);
    if (!Number.isFinite(shareNum) || Number.isNaN(shareNum)) {
      return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be numeric (0,100]' });
    }
    if (shareNum <= 0 || shareNum > 100) {
      return res.json({ status: 'fail', status_code: 1007, message: 'error: share must be in (0,100]' });
    }
    share = Math.round(shareNum * 100) / 100;
    params.set('share', String(share));
  } else if (amountRaw !== undefined) {
    const amountNum = Number(amountRaw);
    if (!Number.isFinite(amountNum) || Number.isNaN(amountNum)) {
      return res.json({ status: 'fail', status_code: 1011, message: 'The specified amount parameter is not numeric' });
    }
    if (amountNum <= 0) {
      return res.json({ status: 'fail', status_code: 1009, message: 'The specified amount must be > 0' });
    }
    amount = Math.round(amountNum * 100) / 100;
    params.set('amount', String(amount));
  } else {
    return res.json({ status: 'fail', status_code: 400, message: 'No share or amount parameter specified' });
  }

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';

  try {
    const url = `${EXPRESS_BASE}unlendRaw?${params.toString()}`;
    console.log(`unlend -> ${url.replace(apiKey, maskedApi)}`);
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));

    const logMsg = `${resp.status === 200 ? 'success' : 'fail'} unlend invoked apiKey: ${maskedApi} / pool: ${pool} / protocol: ${protocol} / network: ${network} / asset: ${asset} / share: ${share ?? 'NA'} / amount: ${amount ?? 'NA'} / platform: ${platform} / response: ${JSON.stringify(data)}`;
    console.log(logMsg);

    if (resp.status === 200) {
      return res.json(data);
    }
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: unlend — pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing unlend: ${e.message}` });
  }
}

router.post('/unlend', handleUnlend);

export default router;
