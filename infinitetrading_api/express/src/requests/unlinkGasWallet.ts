/**
 * requests/unlinkGasWallet.ts — Node port of R gateway's unlinkGasWallet.R
 * (proxies to plumber-api port 8002's unlinkGasWalletHandler in
 * src/api/api.R).
 *
 * PARITY NOTES:
 *  - Gateway layer: basic_check(network, protocol, pool, apiKey) -- fail ->
 *    returned as-is (unlinkGasWalletHandler returns `check` directly, not a
 *    generic re-wrap) -- replicated via toRWireFormat(check).
 *  - Inner (port 8002) layer: isValidApiKey(network, protocol, pool, apiKey)
 *    -- DB check (SELECT 1 FROM gas_wallets WHERE network=? AND protocol=?
 *    AND pool=? AND token=?) -- fail -> 401 "Invalid API key".
 *  - unlinkGasWallet(network, protocol, pool) -> deletePoolEverywhere(): a
 *    cascading delete across gas_wallets, dhedge_sides, dhedge_allocations
 *    for that network+pool (protocol also filters the gas_wallets delete,
 *    but NOT the dhedge_sides/dhedge_allocations deletes -- confirmed from
 *    R source, those two only filter by pool+network).
 */

import { Router, Request, Response } from 'express';
import { dbQuery, dbExecute } from '../db';
import { basicCheck, toRWireFormat } from '../basicCheck';

const router = Router();

async function isValidApiKeyForPool(network: string, protocol: string, pool: string, apiKey: string): Promise<boolean> {
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

/**
 * @openapi
 * /unlinkGasWallet:
 *   delete:
 *     summary: Unlink a gas wallet from a pool and clear its trading state (dhedge_sides, dhedge_allocations)
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: network
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
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Gas wallet unlinked.
 */
router.delete('/unlinkGasWallet', async (req: Request, res: Response) => {
  const networkRaw = String(req.query.network || '').toLowerCase();
  const protocolRaw = String(req.query.protocol || 'dhedge').toLowerCase();
  const poolRaw = String(req.query.pool || '').toLowerCase();
  const apiKey = String(req.query.apiKey || '');

  const check = await basicCheck({ network: networkRaw, protocol: protocolRaw, pool: poolRaw, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  const validForPool = await isValidApiKeyForPool(networkRaw, protocolRaw, poolRaw, apiKey);
  if (!validForPool) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API key'] });
  }

  try {
    const nGw = await dbExecute('DELETE FROM gas_wallets WHERE pool = ? AND network = ? AND protocol = ?', [poolRaw, networkRaw, protocolRaw]);
    const nSides = await dbExecute('DELETE FROM dhedge_sides WHERE pool = ? AND network = ?', [poolRaw, networkRaw]);
    const nAlloc = await dbExecute('DELETE FROM dhedge_allocations WHERE pool = ? AND network = ?', [poolRaw, networkRaw]);
    return res.json({
      status: ['success'],
      status_code: [200],
      deleted: { gas_wallets: [nGw], dhedge_sides: [nSides], dhedge_allocations: [nAlloc] },
      message: [`Deleted pool ${poolRaw}: gas_wallets=${nGw}, dhedge_sides=${nSides}, dhedge_allocations=${nAlloc}`],
    });
  } catch (e: any) {
    console.log(`Error: unlinkGasWallet for protocol: ${protocolRaw} network: ${networkRaw} pool: ${poolRaw} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: [`Error deleting pool: ${e.message}`] });
  }
});

export default router;
