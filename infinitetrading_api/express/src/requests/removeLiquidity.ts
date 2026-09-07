/**
 * requests/removeLiquidity.ts — Node port of the R gateway's removeLiquidity.R
 * (port 8003), which validated then proxied to plumber-api (port 8002), which
 * proxied straight to Express's own POST /removeLiquidity (now renamed
 * /removeLiquidityRaw, see requests/liquidity.ts).
 *
 * ***MONEY-MOVING*** — closes (fully or partially) a UniswapV3 LP position held
 * by a dHEDGE vault. Validation order mirrors removeLiquidity.R exactly.
 *
 * PARITY NOTES (removeLiquidityHandler):
 *  1. network/protocol/platform trimmed + lower-cased; defaults base/dhedge/uniswapv3.
 *  2. basic_check(network, protocol, pool, apiKey) — fail -> returned as-is.
 *  3. platform whitelist {uniswapv3} -> 1010 "Unsupported platform: <p>. Supported: uniswapv3".
 *  4. token_id required -> 1011 "token_id is required"; must be a valid
 *     non-negative integer -> 1011 "token_id must be a valid non-negative
 *     integer" (both verified live).
 *  5. amount must be numeric in (0,100] -> 1007 "amount must be a percentage in
 *     (0, 100]" (verified live).
 *  6. output_asset defaults to "both" when empty/blank.
 *  7. slippage must be numeric in (0,50] -> 1008.
 *  8. Forwarded params: apiKey, network, pool, platform, asset1, asset2,
 *     token_id, amount (2dp), output_asset, slippage (4dp). R does not forward
 *     `protocol` — replicated.
 *  9. 200 -> forward the parsed JSON body through unchanged; otherwise
 *     {status:"fail", status_code:<http status>, message:<parsed body>}.
 *
 * DELIBERATE DEVIATION (one, documented): R validates token_id with
 * as.integer(), which is a signed 32-bit conversion and therefore returns NA
 * (-> a spurious 1011 rejection) for any UniswapV3 NFT id above 2147483647.
 * Position ids are nowhere near that today, so this has never fired, but it is
 * a latent bug that would silently make a legitimate position unclosable. This
 * port validates the token_id as a non-negative integer STRING instead — same
 * accept/reject behavior for every id in existence, without the 32-bit cliff.
 * The underlying raw endpoint already takes the id as a uint256 string.
 *
 * NOTE: like addLiquidity.R, the gateway does NOT do an api_check /
 * isValidTrader here — only basic_check; the raw endpoint authenticates via the
 * apiKey's own signer. Kept identical rather than tightened.
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { notifyApiActivity, maskApiKey } from '../utils/telegram';
import { resolveAsset, assetResolutionFailure } from '../lendingAuth';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

function asNumeric(v: unknown): number {
  if (v === undefined || v === null || v === '') return NaN;
  return Number(v);
}

function round(n: number, digits: number): number {
  const f = Math.pow(10, digits);
  return Math.round(n * f) / f;
}

/**
 * @openapi
 * /removeLiquidity:
 *   post:
 *     summary: Remove liquidity from a UniswapV3 position held in a Chamber vault
 *     description: >
 *       Specify the token_id (the NFT position ID of the vault's UniswapV3
 *       position). Use amount to remove a percentage (default 100 = full exit).
 *       Set output_asset to 'both' to keep both tokens in the vault, or to a
 *       specific token address to automatically swap the other token's proceeds.
 *     tags: [Liquidity]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid], default: base }
 *       - in: query
 *         name: asset1
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: asset2
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: token_id
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: platform
 *         schema: { type: string, enum: [auto, uniswapV3, velodrome, velodromecl, aerodrome, aerodromecl, pancakecl, quickswap, kyberswap, cowswap, pendle, aavev3, compoundv3, fluid, lyra, hyperliquid], default: uniswapv3 }
 *       - in: query
 *         name: amount
 *         description: Percentage of liquidity to remove.
 *         schema: { type: number, default: 100 }
 *       - in: query
 *         name: output_asset
 *         schema: { type: string, default: both }
 *       - in: query
 *         name: slippage
 *         schema: { type: number, default: 0.5 }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *     responses:
 *       200:
 *         description: Liquidity removed; returns the transaction hash.
 *       400:
 *         description: Bad request.
 */
async function handleRemoveLiquidity(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };
  const network = String(q.network ?? 'base').trim().toLowerCase();
  const protocol = String(q.protocol ?? 'dhedge').trim().toLowerCase();
  const platform = String(q.platform ?? 'uniswapv3').trim().toLowerCase();
  const apiKey = String(q.apiKey || '');
  const pool = String(q.pool || '');
  const asset1 = String(q.asset1 || '');
  const asset2 = String(q.asset2 || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  // Accept a token symbol ("USDC") or a contract address. The downstream raw
  // endpoint requires addresses. output_asset is resolved further below, since
  // it also accepts the sentinel value "both".
  const resolvedAssets: Record<string, string> = {};
  for (const [name, raw] of [['asset1', asset1], ['asset2', asset2]] as const) {
    if (!raw) continue;
    const resolved = await resolveAsset(raw, network);
    if (!resolved) return res.json(assetResolutionFailure(raw, network));
    resolvedAssets[name] = resolved;
  }

  if (platform !== 'uniswapv3') {
    return res.json({ status: ['fail'], status_code: [1010], message: [`Unsupported platform: ${platform}. Supported: uniswapv3`] });
  }

  const tokenIdRaw = q.token_id === undefined || q.token_id === null ? '' : String(q.token_id).trim();
  if (tokenIdRaw === '') {
    return res.json({ status: ['fail'], status_code: [1011], message: ['token_id is required'] });
  }
  if (!/^\d+$/.test(tokenIdRaw)) {
    return res.json({ status: ['fail'], status_code: [1011], message: ['token_id must be a valid non-negative integer'] });
  }

  const amountNum = asNumeric(q.amount ?? 100);
  if (Number.isNaN(amountNum) || !Number.isFinite(amountNum) || amountNum <= 0 || amountNum > 100) {
    return res.json({ status: ['fail'], status_code: [1007], message: ['amount must be a percentage in (0, 100]'] });
  }

  let outputAsset = String(q.output_asset ?? 'both').trim();
  if (outputAsset.length === 0) outputAsset = 'both';
  // "both" is a sentinel, not a token — only resolve real asset values.
  if (outputAsset.toLowerCase() !== 'both') {
    const resolvedOutput = await resolveAsset(outputAsset, network);
    if (!resolvedOutput) return res.json(assetResolutionFailure(outputAsset, network));
    outputAsset = resolvedOutput;
  }

  const slippageNum = asNumeric(q.slippage ?? 0.5);
  if (Number.isNaN(slippageNum) || slippageNum <= 0 || slippageNum > 50) {
    return res.json({ status: ['fail'], status_code: [1008], message: ['slippage must be in (0, 50]'] });
  }

  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('network', network);
  params.set('pool', pool);
  params.set('platform', platform);
  params.set('asset1', resolvedAssets['asset1'] ?? asset1);
  params.set('asset2', resolvedAssets['asset2'] ?? asset2);
  params.set('token_id', tokenIdRaw);
  params.set('amount', String(round(amountNum, 2)));
  params.set('output_asset', outputAsset);
  params.set('slippage', String(round(slippageNum, 4)));

  const masked = maskApiKey(apiKey);
  const url = `${EXPRESS_BASE}removeLiquidityRaw?${params.toString()}`;
  console.log(`removeLiquidity gateway url: ${url.replace(apiKey, masked)}`);

  try {
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));
    const ok = resp.status === 200;

    notifyApiActivity({
      status: ok ? 'success' : 'fail',
      endpoint: 'removeLiquidity',
      apiKey,
      fields: { pool, network, platform, asset1, asset2, token_id: tokenIdRaw, amount: round(amountNum, 2), output_asset: outputAsset },
      response: data,
    });

    if (ok) return res.json(data);
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: removeLiquidity — pool: ${pool} network: ${network} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'removeLiquidity', apiKey,
      fields: { pool, network, platform, token_id: tokenIdRaw }, response: e.message,
    });
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing removeLiquidity: ${e.message}` });
  }
}

router.post('/removeLiquidity', handleRemoveLiquidity);

export default router;
