/**
 * requests/botStatus.ts — trader-permission and bot-state lookups.
 *
 * Replaces two R gateway endpoints that were declared but never written:
 * `isPoolTrader` had an empty body and `getBotStatus` returned "Endpoint not
 * available yet". Both are implemented here from their evident intent.
 *
 * Read-only, so they take basicCheck rather than the full trader chain —
 * isPoolTrader in particular has to be callable BY a wallet that may not be
 * the trader, otherwise it could never answer "no".
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';
import { getPoolTrader } from '../dhedgeTrader';

const router = Router();

/**
 * @openapi
 * /isPoolTrader:
 *   get:
 *     summary: Check whether an address is the authorised trader for a vault
 *     description: >-
 *       Returns whether the given address is the on-chain trader for the vault.
 *       Useful for confirming a gas wallet is wired up correctly before
 *       attempting a trade, which otherwise fails with status 1006.
 *     tags: [Bots]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - in: query
 *         name: trader
 *         required: true
 *         description: Address to test against the vault's trader.
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Whether the address is the vault's trader.
 */
router.get('/isPoolTrader', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const trader = String(q.trader || '').toLowerCase();

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  if (!isValidEthereumAddress(trader)) {
    return res.json({ status: 'fail', status_code: 400, message: 'trader must be a valid address' });
  }

  try {
    const poolTrader = await getPoolTrader(protocol, pool);
    if (poolTrader === null) {
      return res.json({ status: 'fail', status_code: 1004, message: 'unable to read the trader for this pool' });
    }
    return res.json({
      status: 'success',
      status_code: 200,
      data: {
        network,
        pool,
        trader,
        poolTrader: poolTrader.toLowerCase(),
        isTrader: poolTrader.toLowerCase() === trader,
      },
    });
  } catch (e: any) {
    console.log(`Error: isPoolTrader pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: 'Internal error checking trader' });
  }
});

/**
 * @openapi
 * /getBotStatus:
 *   get:
 *     summary: Get the configured bot and index state for a single vault
 *     description: >-
 *       Returns whether a trading bot is configured for the vault (its pair,
 *       side and parameters from dhedge_sides), whether index allocations are
 *       configured, and whether a gas wallet is linked. This is the per-vault
 *       counterpart to getAllBots, which lists every bot for a manager.
 *     tags: [Bots]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *     responses:
 *       200:
 *         description: Bot, allocation and gas wallet state for the vault.
 */
router.get('/getBotStatus', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  try {
    const [sides, allocs, wallets] = await Promise.all([
      dbQuery(
        'SELECT pair, side, CAST(threshold AS DOUBLE) AS threshold, max_usd, ' +
          'CAST(share AS DOUBLE) AS share, platform, CAST(slippage AS DOUBLE) AS slippage ' +
          'FROM dhedge_sides WHERE network = ? AND pool = ?',
        [network, pool]
      ),
      dbQuery(
        'SELECT assets, allocations, max_usd FROM dhedge_allocations WHERE network = ? AND pool = ?',
        [network, pool]
      ),
      dbQuery(
        'SELECT wallet_address FROM gas_wallets WHERE network = ? AND pool = ? LIMIT 1',
        [network, pool]
      ),
    ]);

    const alloc: any = allocs[0];
    return res.json({
      status: 'success',
      status_code: 200,
      data: {
        network,
        pool,
        gasWallet: wallets.length > 0 ? wallets[0].wallet_address : null,
        hasBot: sides.length > 0,
        bots: sides,
        hasAllocations: allocs.length > 0,
        allocations: alloc
          ? {
              assets: String(alloc.assets).split('-'),
              allocations: String(alloc.allocations).split('-').map(Number),
              max_usd: Number(alloc.max_usd) || 0,
            }
          : null,
      },
    });
  } catch (e: any) {
    console.log(`Error: getBotStatus pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: 'Internal error fetching bot status' });
  }
});

export default router;
