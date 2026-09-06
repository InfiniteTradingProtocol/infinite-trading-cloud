/**
 * requests/compoundV3.ts — Node port of R gateway's compoundV3 sub-router
 * (src/api/gateway/endpoints/compoundV3.R), mounted at /compoundV3/* in the
 * R gateway (port 8003). Historically: /compoundV3/lend & /compoundV3/unlend
 * -> basic_check() -> Express's own /depositCompoundV3 & /withdrawCompoundV3
 * directly (port 8000, no port-8002 involvement at all — these were never
 * trader-gated in R, replicated faithfully; see aaveV3.ts's header comment
 * for the broader auth-strength discussion across these three sub-routers).
 *
 * PARITY NOTES:
 *  - basic_check() only (network/protocol/apiKey/pool format), no
 *    isValidTrader.
 *  - asset must be a valid ethereum address (fail -> status_code 1004),
 *    lower-cased.
 *  - amount takes precedence over share if amount is numeric and > 0
 *    (rounded to 6 decimals); else share must be numeric in (0,100] (rounded
 *    to 2 decimals); else fail -> status_code 1009.
 *  - Forwards directly to Express's existing /depositCompoundV3 or
 *    /withdrawCompoundV3 (NOT renamed — these were never proxied through a
 *    conflicting public route name, so no *Raw rename was needed for them).
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

async function proxyPost(url: string): Promise<any> {
  const resp = await fetch(url, { method: 'POST' });
  const data: any = await resp.json().catch(() => ({}));
  if (resp.status === 200) return data;
  return { status: 'fail', status_code: resp.status, message: data };
}

function buildShareAmountSuffix(q: any): { suffix: string; error?: { status: string; status_code: number; message: string } } {
  const shareRaw = q.share === undefined ? '100' : String(q.share);
  const amountRaw = q.amount === undefined ? undefined : String(q.amount);
  const shareNum = Number(shareRaw);
  const amountNum = amountRaw === undefined ? NaN : Number(amountRaw);

  if (amountRaw !== undefined && !Number.isNaN(amountNum) && Number.isFinite(amountNum) && amountNum > 0) {
    return { suffix: `&amount=${Math.round(amountNum * 1e6) / 1e6}` };
  }
  if (q.share !== undefined && !Number.isNaN(shareNum) && Number.isFinite(shareNum) && shareNum > 0 && shareNum <= 100) {
    return { suffix: `&share=${Math.round(shareNum * 100) / 100}` };
  }
  return { suffix: '', error: { status: 'fail', status_code: 1009, message: 'Please specify share (1-100) or amount (>0)' } };
}

async function handleLendOrUnlend(req: Request, res: Response, endpoint: 'depositCompoundV3' | 'withdrawCompoundV3') {
  const q = { ...req.query, ...req.body };
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  let asset = String(q.asset || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  if (!isValidEthereumAddress(asset)) {
    return res.json({ status: 'fail', status_code: 1004, message: 'Invalid asset address' });
  }
  asset = asset.toLowerCase();

  let url = `${EXPRESS_BASE}${endpoint}?apiKey=${encodeURIComponent(apiKey)}&network=${network}&pool=${pool}&asset=${asset}`;
  const { suffix, error } = buildShareAmountSuffix(q);
  if (error) return res.json(error);
  url += suffix;

  return res.json(await proxyPost(url));
}

/**
 * @openapi
 * /compoundV3/lend:
 *   post:
 *     summary: (weak-auth sub-router) Supply an asset to Compound V3 (Comet) within a dHEDGE vault
 *     tags: [Lending]
 */
router.post('/compoundV3/lend', (req, res) => handleLendOrUnlend(req, res, 'depositCompoundV3'));

/**
 * @openapi
 * /compoundV3/unlend:
 *   post:
 *     summary: (weak-auth sub-router) Withdraw an asset from Compound V3 (Comet) within a dHEDGE vault
 *     tags: [Lending]
 */
router.post('/compoundV3/unlend', (req, res) => handleLendOrUnlend(req, res, 'withdrawCompoundV3'));

export default router;
