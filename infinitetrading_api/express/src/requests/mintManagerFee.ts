/**
 * requests/mintManagerFee.ts — Node port of the R gateway's mintManagerFee.R
 * (port 8003, `mintFeesHandler`), which validated then proxied to plumber-api
 * (port 8002) /mintFees, which proxied to Express's own GET /mintManagerFee
 * (now renamed /mintManagerFeeRaw, see requests/admin.ts).
 *
 * Mints the accrued performance/management fee for a single vault.
 * PoolLogic.mintManagerFee() is PERMISSIONLESS on dHEDGE (see the longer
 * discussion in mintManagerFeeBatch.ts), so this realises an already-accrued
 * fee rather than moving third-party funds.
 *
 * PARITY NOTES (mintFeesHandler):
 *  1. protocol/pool/network lower-cased.
 *  2. basic_check(network, protocol, pool, apiKey) — fail -> returned as-is in
 *     jsonlite's array wire format (verified live: 1000/1001/1002/1004).
 *  3. Forwards pool, apiKey, network, protocol to the raw endpoint and returns
 *     its parsed JSON body through unchanged on 200; on any other status R
 *     returned the parsed body as-is (NOT wrapped) — replicated.
 *  4. POST only. GET returned 405 on the live gateway; kept POST-only.
 *
 * PRODUCTION BUG THIS FIXES (do not silently drop): the R chain has been
 * BROKEN since /mintFees was removed from api.R (port 8002) as dead code —
 * a live POST to https://api.infinitetrading.io/mintManagerFee currently
 * returns {"error":["404 - Resource Not Found"]} for a valid pool/key. This
 * port restores working behavior by calling the Express implementation
 * directly, which is what the R chain was ultimately reaching anyway.
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { notifyApiActivity, maskApiKey } from '../utils/telegram';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

/**
 * @openapi
 * /mintManagerFee:
 *   post:
 *     summary: Mint accrued performance and management fees for a vault
 *     description: >
 *       Realises the manager fee already accrued by the specified Chamber vault.
 *       The call is permissionless on-chain; the apiKey identifies the gas
 *       wallet that pays for the transaction.
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *     responses:
 *       200:
 *         description: Fee minted; returns the transaction.
 *       400:
 *         description: Bad request.
 *       500:
 *         description: Internal server error.
 */
async function handleMintManagerFee(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };
  const protocol = String(q.protocol ?? 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const params = new URLSearchParams();
  params.set('pool', pool);
  params.set('apiKey', apiKey);
  params.set('network', network);
  params.set('protocol', protocol);

  const masked = maskApiKey(apiKey);
  const url = `${EXPRESS_BASE}mintManagerFeeRaw?${params.toString()}`;
  console.log(`mintManagerFee -> ${url.replace(apiKey, masked)}`);

  try {
    const resp = await fetch(url);
    const data: any = await resp.json().catch(() => ({}));
    const ok = resp.status === 200;

    notifyApiActivity({
      status: ok ? 'success' : 'fail',
      endpoint: 'mintManagerFee',
      apiKey,
      fields: { pool, protocol, network },
      response: data,
    });

    return res.json(data);
  } catch (e: any) {
    console.log(`Error: mintManagerFee — pool: ${pool} network: ${network} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'mintManagerFee', apiKey,
      fields: { pool, protocol, network }, response: e.message,
    });
    return res.json({ status: 'fail', status_code: 500, message: `Internal error executing mintManagerFee: ${e.message}` });
  }
}

router.post('/mintManagerFee', handleMintManagerFee);

export default router;
