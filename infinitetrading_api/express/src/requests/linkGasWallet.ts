/**
 * requests/linkGasWallet.ts — Node port of R gateway's linkGasWallet.R
 * (proxies to plumber-api port 8002's linkGasWalletHandler in src/api/api.R).
 *
 * PARITY NOTES:
 *  - Gateway layer: basic_check(network, protocol, pool, apiKey) -- fail ->
 *    returned as-is (gateway's linkGasWalletHandler just returns `check`
 *    directly on failure, unlike deleteBot's generic 400 re-wrap) —
 *    replicated via toRWireFormat(check) (preserves the original
 *    status_code, e.g. "1000"/"1002"/"1004").
 *  - Inner (port 8002) layer:
 *      1. wallet = getWallet(apiKey) (resolve token -> bound EOA via
 *         Express's own /getWallet).
 *      2. api_check(apiKey, protocol, pool, wallet, network) ==
 *         isValidTrader(protocol, pool, wallet) -- fail -> status_code
 *         "1006" "The trader wallet is not configured as a trader in the
 *         specified pool" (ported via dhedgeTrader.ts's isValidTrader,
 *         built in this same migration effort).
 *      3. linkGasWallet(network, protocol, wallet, pool, apiKey) -- DB
 *         upsert: INSERT INTO gas_wallets (token, wallet_address, manager,
 *         network, protocol, pool, is_active) VALUES (apiKey, wallet, '',
 *         network, protocol, pool, 1) ON DUPLICATE KEY UPDATE
 *         token=VALUES(token), wallet_address=VALUES(wallet_address),
 *         is_active=1.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { isValidTrader } from '../dhedgeTrader';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

async function getWalletForApiKey(apiKey: string): Promise<string | null> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}getWallet?apiKey=${encodeURIComponent(apiKey)}`);
    if (resp.status !== 200) return null;
    const data: any = await resp.json();
    return data && data.msg ? String(data.msg) : null;
  } catch {
    return null;
  }
}

/**
 * @openapi
 * /linkGasWallet:
 *   post:
 *     summary: Link a gas wallet to a pool (wallet must be an authorized trader on the pool)
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
 *         description: Gas wallet linked.
 */
router.post('/linkGasWallet', async (req: Request, res: Response) => {
  const networkRaw = String(req.query.network || '').toLowerCase();
  const protocolRaw = String(req.query.protocol || 'dhedge').toLowerCase();
  const poolRaw = String(req.query.pool || '');
  const apiKey = String(req.query.apiKey || '');

  const check = await basicCheck({ network: networkRaw, protocol: protocolRaw, pool: poolRaw, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  const wallet = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Unable to resolve wallet for API key'] });
  }

  const validTrader = await isValidTrader(protocolRaw, poolRaw, wallet);
  if (!validTrader) {
    return res.json({ status: ['fail'], status_code: ['1006'], message: ['The trader wallet is not configured as a trader in the specified pool'] });
  }

  const poolLower = poolRaw.toLowerCase();
  const walletLower = wallet.toLowerCase();
  try {
    await dbQuery(
      `INSERT INTO gas_wallets (token, wallet_address, manager, network, protocol, pool, is_active)
       VALUES (?, ?, '', ?, ?, ?, 1)
       ON DUPLICATE KEY UPDATE token=VALUES(token), wallet_address=VALUES(wallet_address), is_active=1`,
      [apiKey, walletLower, networkRaw, protocolRaw, poolLower]
    );
    return res.json({ status: ['success'], status_code: [200], message: ['Gas wallet successfully linked'] });
  } catch (e: any) {
    console.log(`Error: linkGasWallet — protocol: ${protocolRaw} network: ${networkRaw} wallet: ${walletLower} pool: ${poolLower} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error linking gas wallet'] });
  }
});

export default router;
