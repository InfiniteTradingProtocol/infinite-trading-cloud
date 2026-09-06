/**
 * requests/addLiquidity.ts — Node port of the R gateway's addLiquidity.R
 * (port 8003), which validated then proxied to plumber-api (port 8002), which
 * proxied straight to Express's own POST /addLiquidity (now renamed
 * /addLiquidityRaw, see requests/liquidity.ts).
 *
 * ***MONEY-MOVING*** — opens a UniswapV3 LP position inside a dHEDGE vault.
 * Validation order mirrors addLiquidity.R exactly.
 *
 * PARITY NOTES (addLiquidityHandler):
 *  1. network/protocol/platform trimmed + lower-cased; defaults base/dhedge/uniswapv3.
 *  2. basic_check(network, protocol, pool, apiKey) — fail -> returned as-is in
 *     jsonlite's array wire format.
 *  3. platform whitelist {uniswapv3} -> 1010 "Unsupported platform: <p>. Supported: uniswapv3"
 *     (verified live).
 *  4. fee_tier whitelist {500,3000,10000} -> 1011 "fee_tier must be one of: 500, 3000, 10000".
 *  5. amount (if supplied AND numeric) must be > 0 -> 1007; else share (if
 *     supplied AND numeric) must be in (0,100] -> 1007. Note R's else-if: a
 *     non-numeric amount falls through to the share branch, and a non-numeric
 *     share is silently skipped — replicated faithfully.
 *  6. slippage must be numeric in (0,50] -> 1008 (verified live).
 *  7. Forwarded params: apiKey, network, pool, platform, asset1, asset2,
 *     input_asset, fee_tier (as integer), slippage (4dp), then EITHER amount
 *     (raw, when positive+numeric) OR share (2dp), then optional
 *     lower_price/upper_price. Note R never forwards `protocol` — replicated.
 *  8. 200 -> forward the parsed JSON body through unchanged;
 *     otherwise {status:"fail", status_code:<http status>, message:<parsed body>}.
 *
 * NOTE: R's gateway does NOT do an api_check / isValidTrader here — only
 * basic_check. The underlying raw endpoint authenticates by loading the vault
 * with the apiKey's own signer, so a non-trader key simply cannot execute.
 * Kept identical rather than tightened, to avoid changing production behavior
 * during a migration.
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { notifyApiActivity, maskApiKey } from '../utils/telegram';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

/** R's suppressWarnings(as.numeric(x)): non-numeric / absent -> NaN. */
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
 * /addLiquidity:
 *   post:
 *     summary: Add liquidity to a UniswapV3 pool through a Chamber vault
 *     description: >
 *       Provide input_asset (the source token to use), asset1 and asset2 (the
 *       pair tokens), and optionally lower_price/upper_price for a concentrated
 *       position (full range by default). The input_asset is automatically split
 *       and swapped to the correct ratio before providing liquidity. Use
 *       fee_tier 500 for stable pairs, 3000 for most pairs, 10000 for exotic pairs.
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
 *         name: input_asset
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: platform
 *         schema: { type: string, enum: [auto, uniswapV3, velodrome, velodromecl, aerodrome, aerodromecl, pancakecl, quickswap, kyberswap, cowswap, pendle, aavev3, compoundv3, fluid, lyra, hyperliquid], default: uniswapv3 }
 *       - in: query
 *         name: fee_tier
 *         schema: { type: integer, default: 3000, enum: [500, 3000, 10000] }
 *       - in: query
 *         name: lower_price
 *         schema: { type: number }
 *       - in: query
 *         name: upper_price
 *         schema: { type: number }
 *       - in: query
 *         name: share
 *         description: Percentage of the input_asset balance to use.
 *         schema: { type: number, default: 100 }
 *       - in: query
 *         name: amount
 *         description: Explicit token amount (overrides share when set).
 *         schema: { type: number }
 *       - in: query
 *         name: slippage
 *         schema: { type: number, default: 0.5 }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *     responses:
 *       200:
 *         description: Liquidity added; returns the transaction hash.
 *       400:
 *         description: Bad request.
 */
async function handleAddLiquidity(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };
  const network = String(q.network ?? 'base').trim().toLowerCase();
  const protocol = String(q.protocol ?? 'dhedge').trim().toLowerCase();
  const platform = String(q.platform ?? 'uniswapv3').trim().toLowerCase();
  const apiKey = String(q.apiKey || '');
  const pool = String(q.pool || '');
  const asset1 = String(q.asset1 || '');
  const asset2 = String(q.asset2 || '');
  const inputAsset = String(q.input_asset || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  if (platform !== 'uniswapv3') {
    return res.json({ status: ['fail'], status_code: [1010], message: [`Unsupported platform: ${platform}. Supported: uniswapv3`] });
  }

  const feeTier = parseInt(String(q.fee_tier ?? 3000), 10);
  if (!Number.isInteger(feeTier) || ![500, 3000, 10000].includes(feeTier)) {
    return res.json({ status: ['fail'], status_code: [1011], message: ['fee_tier must be one of: 500, 3000, 10000'] });
  }

  const shareRaw = q.share ?? 100;
  const amountRaw = q.amount;
  const shareNum = asNumeric(shareRaw);
  const amountNum = asNumeric(amountRaw);

  const amountGiven = amountRaw !== undefined && amountRaw !== null && !Number.isNaN(amountNum);
  if (amountGiven) {
    if (!Number.isFinite(amountNum) || amountNum <= 0) {
      return res.json({ status: ['fail'], status_code: [1007], message: ['amount must be a positive number'] });
    }
  } else if (!Number.isNaN(shareNum)) {
    if (!Number.isFinite(shareNum) || shareNum <= 0 || shareNum > 100) {
      return res.json({ status: ['fail'], status_code: [1007], message: ['share must be in (0, 100]'] });
    }
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
  params.set('asset1', asset1);
  params.set('asset2', asset2);
  params.set('input_asset', inputAsset);
  params.set('fee_tier', String(feeTier));
  params.set('slippage', String(round(slippageNum, 4)));

  if (amountGiven && Number.isFinite(amountNum) && amountNum > 0) {
    params.set('amount', String(amountRaw));
  } else if (!Number.isNaN(shareNum) && Number.isFinite(shareNum)) {
    params.set('share', String(round(shareNum, 2)));
  }

  const lowerPrice = asNumeric(q.lower_price);
  const upperPrice = asNumeric(q.upper_price);
  if (!Number.isNaN(lowerPrice)) params.set('lower_price', String(lowerPrice));
  if (!Number.isNaN(upperPrice)) params.set('upper_price', String(upperPrice));

  const masked = maskApiKey(apiKey);
  const url = `${EXPRESS_BASE}addLiquidityRaw?${params.toString()}`;
  console.log(`addLiquidity gateway url: ${url.replace(apiKey, masked)}`);

  try {
    const resp = await fetch(url, { method: 'POST' });
    const data: any = await resp.json().catch(() => ({}));
    const ok = resp.status === 200;

    notifyApiActivity({
      status: ok ? 'success' : 'fail',
      endpoint: 'addLiquidity',
      apiKey,
      fields: { pool, network, platform, asset1, asset2, input_asset: inputAsset, fee_tier: feeTier },
      response: data,
    });

    if (ok) return res.json(data);
    return res.json({ status: 'fail', status_code: resp.status, message: data });
  } catch (e: any) {
    console.log(`Error: addLiquidity — pool: ${pool} network: ${network} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'addLiquidity', apiKey,
      fields: { pool, network, platform }, response: e.message,
    });
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing addLiquidity: ${e.message}` });
  }
}

router.post('/addLiquidity', handleAddLiquidity);

export default router;
