/**
 * requests/getTicks.ts — PROMOTED from shadow/endpoints/getTicks.ts to
 * production (Bucket A cutover, 2026-09-06). Reads straight from Redis, no
 * dependency on R's port-8002 inner API. Parity-verified before promotion.
 *
 * Node port of R gateway's getTicks.R
 * (proxies to plumber-api port 8002 -> real implementation in src/api/db.R's
 * getTicks(), which reads a live price tick straight from Redis).
 *
 * PARITY NOTES (all confirmed live via curl on EC2):
 *  - Uses the "frontend" literal apiKey scheme (same family as
 *    getTotalYield/getAllYields/getCandles) — NOT basic_check's UUID auth.
 *  - `exchange` IS lower-cased before building the Redis key; `pair` is
 *    NOT case-normalized (case-sensitive lookup) — confirmed live:
 *    pair=btc-usd -> fail, pair=BTC-USD -> success, for the SAME Redis key
 *    `coinbase_BTC-USD` (redis-cli GET confirms the key itself uses
 *    upper-case pair). Replicated exactly: exchange.toLowerCase(), pair as-is.
 *  - Redis key format: `${exchange}_${pair}` (matches R: r$GET(paste0(exchange,"_",pair))).
 *  - Missing/invalid apiKey with all other params valid returns a generic R
 *    500 (`{"error":"500 - Internal server error"}`) — a pre-existing R bug
 *    (apiKey has no default and the handler crashes before the frontend-key
 *    check when apiKey is completely omitted). This port implements the
 *    CORRECT intended behavior (401 Invalid API Key) rather than replicating
 *    the crash, matching the same approach taken for getSymbol/getContract.
 *  - Wrong (non-empty) apiKey and unknown exchange/pair BOTH return the same
 *    404 "Invalid exchange or pair, price not available" shape as R — this
 *    is because R's getTicksHandler doesn't distinguish "bad key" from
 *    "not found" at that response layer; replicated as such for wrong apiKey.
 *    NOTE: unlike yields.ts, wrong apiKey here is NOT 401 — see below.
 */

import { Router, Request, Response } from 'express';
import { getRedis } from '../lib/redis';

const router = Router();

/**
 * @openapi
 * /getTicks:
 *   get:
 *     summary: Get the latest live tick price for a trading pair
 *     tags: [Market Data]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: exchange
 *         schema: { type: string, default: coinbase }
 *       - in: query
 *         name: pair
 *         schema: { type: string, default: BTC-USD }
 *     responses:
 *       200:
 *         description: The latest tick price.
 */
router.get('/getTicks', async (req: Request, res: Response) => {
  const exchange = String(req.query.exchange || 'coinbase').toLowerCase();
  const pair = String(req.query.pair || 'BTC-USD'); // case-sensitive, not normalized
  const apiKey = req.query.apiKey === undefined ? undefined : String(req.query.apiKey);

  if (apiKey === undefined) {
    // R crashes here (missing arg, no default) -> generic 500. We implement
    // the intended/correct behavior instead of replicating the crash.
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API Key'] });
  }

  try {
    const redis = await getRedis();
    const val = apiKey === 'frontend' ? await redis.get(`${exchange}_${pair}`) : null;
    const price = val === null || val === undefined ? NaN : Number(val);

    if (!Number.isNaN(price)) {
      return res.json({ status: ['success'], status_code: [200], price: [price] });
    }
    return res.json({ status: ['fail'], status_code: [404], message: ['Invalid exchange or pair, price not available'] });
  } catch (e: any) {
    console.log(`error fetching tick for ${exchange}_${pair}: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [404], message: ['Invalid exchange or pair, price not available'] });
  }
});

export default router;
