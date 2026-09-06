/**
 * shadow/endpoints/getAssociatedGasWallets.ts — Node port of R gateway's
 * getAssociatedGasWallets.R (proxies to plumber-api port 8002's
 * getAssociatedGasWalletsHandler in src/api/api.R).
 *
 * PARITY NOTES:
 *  - Requires apiKey === "frontend" (literal, not basic_check UUID scheme) —
 *    confirmed in R source: `if (apiKey != "frontend") return(fail 401)`.
 *  - Requires manager + signature (EIP-191/EIP-1271), verified via the
 *    ALREADY LIVE production Express /verifySignature endpoint (port 8000)
 *    — same reasoning as gasBalance.ts: reuse existing audited signature
 *    verification rather than reimplementing it.
 *  - Missing apiKey/manager/signature -> 400 "Missing required parameters"
 *    (checked BEFORE the apiKey=="frontend" check, confirmed from source
 *    order: `if (is.null(apiKey) || is.null(manager) || is.null(signature))`
 *    is the very first check in getAssociatedGasWalletsHandler).
 *  - DB query: SELECT wallet_address AS wallet, label, token AS apiKey
 *    FROM gas_wallets WHERE manager = ? AND pool IS NULL
 *    (src/api/db.R's getAssociatedGasWallets(), noKeys=FALSE branch — the
 *    apiKey/token IS included in the response here, unlike getAllGasBalance's
 *    internal noKey=TRUE call to the same underlying function).
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../../db';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';
const SIGNATURE_MESSAGE =
  'Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations.';

async function verifySignatureViaExpress(signature: string, manager: string, network?: string): Promise<boolean> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}verifySignature`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: SIGNATURE_MESSAGE, signature, expectedAddress: manager, network }),
    });
    const data: any = await resp.json();
    return resp.status === 200 && data.status === 'success' && !!data.isValid;
  } catch {
    return false;
  }
}

router.get('/getAssociatedGasWallets', async (req: Request, res: Response) => {
  const apiKey = req.query.apiKey === undefined ? undefined : String(req.query.apiKey);
  const manager = req.query.manager === undefined ? undefined : String(req.query.manager);
  const signature = req.query.signature === undefined ? undefined : String(req.query.signature);
  const network = req.query.network === undefined ? undefined : String(req.query.network);

  if (apiKey === undefined || manager === undefined || signature === undefined) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Missing required parameters: apiKey, manager, or signature'] });
  }
  if (apiKey !== 'frontend') {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API Key'] });
  }
  if (!/^0x[0-9a-fA-F]{130,}$/.test(signature) || !(await verifySignatureViaExpress(signature, manager, network))) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(manager)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Wallet or Manager'] });
  }

  try {
    const rows = await dbQuery(
      'SELECT wallet_address AS wallet, label, token AS apiKey FROM gas_wallets WHERE manager = ? AND pool IS NULL',
      [manager.toLowerCase()]
    );
    return res.json(rows);
  } catch (e: any) {
    console.log(`Error: getAssociatedGasWallets — manager: ${manager} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error listing associated gas wallets'] });
  }
});

export default router;
