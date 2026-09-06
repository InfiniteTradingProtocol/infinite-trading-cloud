/**
 * requests/deleteBot.ts — Node port of R gateway's deleteBot.R (proxies to
 * plumber-api port 8002's deleteBotHandler -> db.R's deleteBot()).
 *
 * PARITY NOTES:
 *  - Gateway layer: requires apiKey, network, pool (protocol defaults to
 *    "dhedge") -- missing any -> 400 "Missing required parameters: ...".
 *    Then basic_check(network, protocol, pool, apiKey) (UUID apiKey scheme,
 *    same family as getGasBalance/getGasWalletPools) -- fail -> 400 with
 *    check's own message (gateway wraps ALL basic_check failures as generic
 *    400, not the original status_code -- confirmed from R source:
 *    `if (!is.null(check$status) && check$status == "fail") return(list(status="fail",status_code=400,message=check$message))`).
 *  - Inner (port 8002) layer: isValidApiKey(network, protocol, pool, apiKey)
 *    -- a DB check (SELECT 1 FROM gas_wallets WHERE network=? AND protocol=?
 *    AND pool=? AND token=?) -- fail -> 401 "Invalid API key" (note: this is
 *    the SAME apiKey validated twice, first as a UUID format then as a real
 *    linked gas-wallet token -- both must pass).
 *  - deleteBot() itself: DELETE FROM dhedge_sides WHERE network=? AND pool=?
 *    (protocol is accepted but NOT used in the WHERE clause -- confirmed
 *    from R source, deletes across all protocols for that network+pool).
 *  - Response is a straight pass-through in R (gateway wraps the port-8002
 *    response in its own success/fail/message shape from the raw JSON body)
 *    -- replicated by returning success/status_code/message directly from
 *    the single, combined check+delete flow (no real inter-process hop
 *    needed once both R hops collapse into one Express handler).
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck } from '../basicCheck';

const router = Router();

async function isValidApiKeyForPool(network: string, protocol: string, pool: string, apiKey: string): Promise<boolean> {
  try {
    const rows = await dbQuery(
      'SELECT 1 FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ? AND token = ? LIMIT 1',
      [network.toLowerCase(), protocol, pool.toLowerCase(), apiKey]
    );
    return rows.length > 0;
  } catch (e: any) {
    console.log('Error: isValidApiKeyForPool:', e.message);
    return false;
  }
}

/**
 * @openapi
 * /deleteBot:
 *   delete:
 *     summary: Delete a trading bot's side configuration for a pool (turns off the bot)
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, default: dhedge }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Bot deleted.
 */
router.delete('/deleteBot', async (req: Request, res: Response) => {
  const apiKey = String(req.query.apiKey || '');
  const protocolRaw = String(req.query.protocol || 'dhedge').toLowerCase();
  const networkRaw = String(req.query.network || '').toLowerCase();
  const poolRaw = String(req.query.pool || '').toLowerCase();

  const missing: string[] = [];
  if (!apiKey) missing.push('apiKey');
  if (!networkRaw) missing.push('network');
  if (!poolRaw) missing.push('pool');
  if (missing.length > 0) {
    return res.json({ status: ['fail'], status_code: [400], message: [`Missing required parameters: ${missing.join(', ')}`] });
  }

  const check = await basicCheck({ network: networkRaw, protocol: protocolRaw, pool: poolRaw, apiKey });
  if (check.status === 'fail') {
    // Gateway layer wraps ANY basic_check failure as a generic 400 with the
    // check's own message (not the original status_code).
    return res.json({ status: ['fail'], status_code: [400], message: [check.message] });
  }

  const validForPool = await isValidApiKeyForPool(networkRaw, protocolRaw, poolRaw, apiKey);
  if (!validForPool) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API key'] });
  }

  try {
    await dbQuery('DELETE FROM dhedge_sides WHERE network = ? AND pool = ?', [networkRaw, poolRaw]);
    return res.json({ status: ['success'], status_code: [200], message: [`Bot successfully deleted: ${poolRaw}`] });
  } catch (e: any) {
    console.log(`Error: deleteBot for protocol: ${protocolRaw} network: ${networkRaw} pool: ${poolRaw} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error deleting bot entry'] });
  }
});

export default router;
