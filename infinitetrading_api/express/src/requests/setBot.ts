/**
 * requests/setBot.ts — Node port of R gateway's setBot.R (proxies to
 * plumber-api port 8002's setSideHandler in src/api/api.R, which itself
 * writes to `dhedge_sides` and then invokes executeTrades()).
 *
 * ***HIGH RISK — LIVE TRADING.*** This endpoint both persists the bot's
 * strategy configuration AND immediately triggers a live rebalance via the
 * full tradebot/executeTrades decision engine (see ../tradeEngine.ts).
 *
 * PARITY NOTES:
 *  - Gateway layer (setBot.R):
 *      1. Normalize case (protocol/pool/network/side/platform lowercased).
 *      2. lending defaults to FALSE if null/non-logical.
 *      3. basic_check(network, protocol, pool, apiKey) -- fail -> returned.
 *      4. side must be one of hold/neutral/short/long (else 1008).
 *      5. side=="short" requires network in [arbitrum, optimism] (else 400).
 *      6. threshold must be a number in [0,100] (else 400), rounded to 2dp.
 *      7. share must be a number in [1,100] (else 400), rounded to 2dp.
 *      8. max_usd (if provided) must be numeric > 0 (else 400), rounded 2dp.
 *      9. Proxies to inner /setSide with all params + lending.
 *  - Inner (port 8002) layer (setSideHandler in api.R):
 *      1. isValidApiKey(network, protocol, pool, apiKey) DB check (gas
 *         wallet linked to pool) -- fail -> 401 "Invalid API key".
 *      2. side=="short" re-checked against short_networks (redundant with
 *         gateway check, kept for parity -- defi.R's short_networks list is
 *         identical to the gateway's).
 *      3. setSide(...) -- upserts the dhedge_sides row (db.R's setSide()).
 *      4. executeTrades(...) -- fire-and-forget-ish (result is logged, not
 *         propagated to the response) trade execution based on the new
 *         side/threshold/share/max_usd/platform.
 *      5. Returns the result of setSide() (NOT executeTrades()'s result) --
 *         i.e. the HTTP response reflects "was the DB write successful",
 *         while the actual trade execution result is only logged
 *         server-side. This is intentional/existing behavior (executeTrades
 *         can legitimately fail without failing the overall /setBot call,
 *         e.g. "hold" side, or a trade that doesn't meet threshold), so it
 *         is preserved here exactly.
 */

import { Router, Request, Response } from 'express';
import { dbExecute } from '../db';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { executeTrades } from '../tradeEngine';
import { DEFAULT_PLATFORM } from '../utils/parseDapp';

const router = Router();

const SHORT_NETWORKS = ['arbitrum', 'optimism'];

async function isValidApiKeyForPool(network: string, protocol: string, pool: string, apiKey: string): Promise<boolean> {
  const { dbQuery } = await import('../db');
  try {
    const rows = await dbQuery(
      'SELECT 1 FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ? AND token = ? LIMIT 1',
      [network, protocol, pool, apiKey]
    );
    return rows.length > 0;
  } catch (e: any) {
    console.log('Error: isValidApiKeyForPool:', e.message);
    return false;
  }
}

// setSide (db.R lines 232-238): upserts dhedge_sides.
async function setSide(opts: {
  network: string; pool: string; pair: string; side: string; threshold: number;
  maxUsd: number; share: number; platform: string; slippage: number;
}): Promise<{ status: string; status_code: number; message: string }> {
  try {
    const pair = opts.pair.toUpperCase();
    await dbExecute(
      `INSERT INTO dhedge_sides (network, pool, pair, side, threshold, max_usd, share, platform, slippage)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE side=VALUES(side), threshold=VALUES(threshold),
       max_usd=VALUES(max_usd), share=VALUES(share), platform=VALUES(platform), slippage=VALUES(slippage)`,
      [opts.network, opts.pool, pair, opts.side, opts.threshold, Math.trunc(opts.maxUsd), opts.share, opts.platform, opts.slippage]
    );
    return { status: 'success', status_code: 200, message: 'Sides submitted successfully' };
  } catch (e: any) {
    console.log(`Error: setSide for network: ${opts.network} pool: ${opts.pool} error: ${e.message}`);
    return { status: 'fail', status_code: 500, message: 'Internal error submitting sides' };
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * @openapi
 * /setBot:
 *   post:
 *     summary: Set the trading-bot strategy (side/threshold/share) for a pool and trigger a rebalance (HIGH RISK, live trading)
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *       - in: query
 *         name: pair
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: side
 *         required: true
 *         schema: { type: string, enum: [long, short, hold, neutral] }
 *       - in: query
 *         name: threshold
 *         schema: { type: number, default: 1 }
 *       - in: query
 *         name: max_usd
 *         schema: { type: number, default: 10000000 }
 *       - in: query
 *         name: slippage
 *         schema: { type: number, default: 1 }
 *       - in: query
 *         name: share
 *         schema: { type: number, default: 100 }
 *       - in: query
 *         name: platform
 *         schema: { type: string, enum: [auto, uniswapV3, velodrome, velodromecl, aerodrome, aerodromecl, pancakecl, quickswap, kyberswap, cowswap, pendle, aavev3, compoundv3, fluid, lyra, hyperliquid], default: auto }
 *       - in: query
 *         name: lending
 *         schema: { type: boolean, default: false }
 *     responses:
 *       200:
 *         description: Sides submitted successfully (trade execution result is logged server-side only).
 */
router.post('/setBot', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const pair = String(q.pair || '');
  const side = String(q.side || '').toLowerCase();
  const platform = String(q.platform || DEFAULT_PLATFORM).toLowerCase();
  let lending = false;
  if (typeof q.lending === 'boolean') lending = q.lending;
  else if (typeof q.lending === 'string') lending = q.lending.toLowerCase() === 'true';

  // === Gateway layer: basicCheck ===
  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  const maxUsdRaw = q.max_usd === undefined ? '10000000' : String(q.max_usd);
  const slippageRaw = q.slippage === undefined ? '1' : String(q.slippage);
  const shareRaw = q.share === undefined ? '100' : String(q.share);
  const thresholdRaw = q.threshold === undefined ? '1' : String(q.threshold);

  const maxUsdNum = Number(maxUsdRaw);
  const slippageNum = Number(slippageRaw);
  const shareNum = Number(shareRaw);
  const thresholdNum = Number(thresholdRaw);

  // === Gateway layer: side validation ===
  if (!['hold', 'neutral', 'short', 'long'].includes(side)) {
    return res.json({ status: ['fail'], status_code: [1008], message: ['The specified side must be one of: long, short, hold, or neutral.'] });
  }
  if (side === 'short' && !SHORT_NETWORKS.includes(network)) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Shorts only supported on Arbitrum or Optimism.'] });
  }

  // === Gateway layer: threshold validation ===
  if (Number.isNaN(thresholdNum) || thresholdNum < 0 || thresholdNum > 100) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Threshold must be number in the range [0, 100].'] });
  }
  const threshold = round2(thresholdNum);

  // === Gateway layer: share validation ===
  if (Number.isNaN(shareNum) || shareNum < 1 || shareNum > 100) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Share must be a number in the range [1, 100].'] });
  }
  const share = round2(shareNum);

  // === Gateway layer: max_usd validation ===
  if (Number.isNaN(maxUsdNum)) {
    return res.json({ status: ['fail'], status_code: [400], message: ['The specified max_usd is not numeric.'] });
  }
  if (maxUsdNum <= 0) {
    return res.json({ status: ['fail'], status_code: [400], message: ['The specified max_usd must be a number > 0.'] });
  }
  const maxUsd = round2(maxUsdNum);

  // === Inner layer: isValidApiKey DB check ===
  const validForPool = await isValidApiKeyForPool(network, protocol, pool, apiKey);
  if (!validForPool) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API key'] });
  }

  // === Inner layer: re-check short_networks (parity with R's redundant check) ===
  if (side === 'short' && !SHORT_NETWORKS.includes(network)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Shorting is not allowed on the specified network'] });
  }

  // === Inner layer: setSide DB upsert ===
  const setSideResult = await setSide({ network, pool, pair, side, threshold, maxUsd, share, platform, slippage: slippageNum });
  console.log(`/setSide: ${JSON.stringify(setSideResult)}`);

  // === Inner layer: executeTrades (result logged only, not returned) ===
  executeTrades({
    pool, pair, side: side as any, share, threshold, slippage: slippageNum,
    apiKey, maxUsd, composition: null, platform, protocol, network,
  }).then((executeTradesRes) => {
    console.log(`/setSide: executeTrades response: ${JSON.stringify(executeTradesRes)}`);
  }).catch((e) => {
    console.log(`/setSide: executeTrades error: ${e.message}`);
  });

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';
  console.log(`setBot invoked | apiKey: ${maskedApi} / pool: ${pool} / protocol: ${protocol} / network: ${network} / pair: ${pair} / side: ${side} / threshold: ${threshold} / max_usd: ${maxUsd} / slippage: ${slippageNum} / share: ${share} / platform: ${platform} / lending: ${lending}`);

  return res.json({ status: [setSideResult.status], status_code: [setSideResult.status_code], message: [setSideResult.message] });
});

export default router;
