/**
 * requests/poolCompositionEnriched.ts — Node port of R gateway's
 * poolComposition.R (proxies to port-8002's poolCompositionHandler, which
 * calls pool_comp() -> dhedge_pool_comp()).
 *
 * NOTE: This is a DIFFERENT endpoint than Express's existing raw
 * /poolComposition in requests/admin.ts (which returns the SDK's raw
 * 4-field-per-asset shape: asset, isDeposit, balance{BigNumber},
 * rate{BigNumber} — used internally by tradeEngine.ts and trade.ts). This
 * one replicates R's ENRICHED 6-column shape (asset, isDeposit, assetPair,
 * symbol, amount, price — decimal-adjusted, symbol-resolved) that the
 * public gateway actually returned, via tradeEngine.ts's poolComp() helper
 * (the same enrichment logic used internally by the tradebot engine).
 *
 * Since both R's gateway (poolComposition.R) and inner (api.R) handlers used
 * the *same* function name/route, and only the gateway layer added
 * basic_check, this single route replicates the gateway's exact behavior
 * end-to-end (basicCheck, then delegate to the enrichment logic).
 *
 * PARITY NOTES:
 *  - basic_check(pool, network, protocol, apiKey) -- fail -> returned as-is.
 *  - Then calls pool_comp(pool, network, protocol) directly (no apiKey
 *    passed through to the inner call in R's gateway wrapper) and returns
 *    its enriched composition array.
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { poolComp } from '../tradeEngine';

const router = Router();

/**
 * @openapi
 * /poolComposition:
 *   get:
 *     summary: Get the enriched (symbol-resolved, decimal-adjusted) composition of a Chamber/deFund pool
 *     tags: [Pools]
 *     parameters:
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Array of { asset, isDeposit, assetPair, symbol, amount, price }.
 */
router.get('/poolComposition', async (req: Request, res: Response) => {
  const poolRaw = String(req.query.pool || '').toLowerCase();
  const networkRaw = String(req.query.network || '').toLowerCase();
  const protocolRaw = String(req.query.protocol || 'dhedge').toLowerCase();
  const apiKey = String(req.query.apiKey || '');

  const check = await basicCheck({ pool: poolRaw, network: networkRaw, protocol: protocolRaw, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  try {
    const comp = await poolComp(poolRaw, networkRaw, protocolRaw);
    if (!comp) {
      return res.json([]);
    }
    return res.json(comp);
  } catch (e: any) {
    console.log(`Error: poolCompositionEnriched — pool: ${poolRaw} network: ${networkRaw} error: ${e.message}`);
    return res.status(500).json({ status: 'fail', message: e.message });
  }
});

export default router;
