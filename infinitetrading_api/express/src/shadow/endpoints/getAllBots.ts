/**
 * shadow/endpoints/getAllBots.ts — Node port of R gateway's getAllBots.R
 * (proxies to plumber-api port 8002's getAllBotsHandler in src/api/api.R,
 * backed by src/api/db.R's getBots()).
 *
 * PARITY NOTES:
 *  - manager+signature (EIP-191/EIP-1271) auth, verified via the ALREADY
 *    LIVE production Express /verifySignature endpoint (port 8000) — same
 *    reasoning as gasBalance.ts/getAssociatedGasWallets.ts: reuse existing
 *    audited signature verification code.
 *  - sigNetwork (network where the Safe multisig lives, for EIP-1271) falls
 *    back to `network` if not supplied (R: `sig_net <- if (!is.null(sigNetwork)...) else network`).
 *  - `network` param here is a BOT-LIST FILTER, not the sig verification
 *    network — confirmed from source comment. Passed through to getBots()
 *    as filterNetwork; NULL/"all" means no filter.
 *  - Query: LEFT JOIN gas_wallets + dhedge_sides on pool+network, filtered to
 *    rows where `pair` isn't NULL (i.e. an actual bot config exists) —
 *    replicated in a single SQL query with the NULL-pair rows excluded at
 *    the DB layer for simplicity (equivalent net result to R's row-by-row
 *    `if (!is.na(row$pair))` filter after the fact).
 *  - `threshold`, `share`, `slippage` are FLOAT columns — MySQL's node-mysql
 *    text protocol truncates these to ~6 significant digits (same bug found
 *    in getCandles.ts), so they're CAST to DOUBLE in SQL to recover full
 *    precision, matching what R's DBI driver reads natively. NOT rounded
 *    further — R doesn't round these values before returning them (no
 *    round()/toJSON digits=4 truncation observed on this response's nested
 *    fields, matching the getAllYields nested-value precedent).
 *  - Empty bots list -> `{"status":["success"],"status_code":[200],"bots":[]}`.
 *
 * PARITY WARNING: confirmed live that the R gateway CRASHES with a generic
 * 500-shaped error (`{"error":["Internal server error: argument \"signature\"
 * is missing, with no default"]}`) when `signature` is omitted entirely —
 * same category of pre-existing bug as getSymbol/getContract's missing-arg
 * crash. This port implements the CORRECT intended behavior (401 Invalid
 * Signature) instead of replicating the crash.
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

/**
 * @openapi
 * /getAllBots:
 *   get:
 *     summary: List all bot configurations for a manager (manager-signed, doc-hidden)
 *     tags: [Bots]
 *     parameters:
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, default: dhedge }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Array of bot configuration records.
 */
router.get('/getAllBots', async (req: Request, res: Response) => {
  const manager = req.query.manager === undefined ? undefined : String(req.query.manager);
  const protocol = String(req.query.protocol || 'dhedge');
  const signature = req.query.signature === undefined ? undefined : String(req.query.signature);
  const network = req.query.network === undefined ? undefined : String(req.query.network);
  const sigNetwork = req.query.sigNetwork === undefined ? undefined : String(req.query.sigNetwork);

  const sigNet = sigNetwork && sigNetwork.length > 0 ? sigNetwork : network;

  if (
    manager === undefined ||
    signature === undefined ||
    !/^0x[0-9a-fA-F]{130,}$/.test(signature) ||
    !(await verifySignatureViaExpress(signature, manager, sigNet))
  ) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(manager)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The manager address is invalid'] });
  }

  try {
    const managerLower = manager.toLowerCase();
    const assoc = await dbQuery(
      'SELECT wallet_address AS wallet FROM gas_wallets WHERE manager = ? AND pool IS NULL',
      [managerLower]
    );
    if (assoc.length === 0) {
      return res.json({ status: ['success'], status_code: [200], bots: [] });
    }

    const useNetFilter = !!(network && network.length > 0 && network.toLowerCase() !== 'all');
    const wallets = assoc.map((r) => r.wallet);
    const placeholders = wallets.map(() => '?').join(',');
    const netClause = useNetFilter ? ' AND gw.network = ?' : '';
    const query =
      `SELECT gw.network, gw.pool, gw.wallet_address AS gasWallet, ` +
      `ds.pair, ds.side, CAST(ds.threshold AS DOUBLE) AS threshold, ds.max_usd, ` +
      `CAST(ds.share AS DOUBLE) AS share, ds.platform, CAST(ds.slippage AS DOUBLE) AS slippage ` +
      `FROM gas_wallets gw ` +
      `LEFT JOIN dhedge_sides ds ON ds.pool = gw.pool AND ds.network = gw.network ` +
      `WHERE gw.protocol = ? AND gw.pool IS NOT NULL AND gw.wallet_address IN (${placeholders})${netClause} ` +
      `AND ds.pair IS NOT NULL`;
    const params = [protocol, ...wallets];
    if (useNetFilter) params.push(network!.toLowerCase());

    const rows = await dbQuery(query, params);
    const bots = rows.map((row) => ({
      pool: row.pool,
      gasWallet: row.gasWallet,
      network: row.network,
      pair: row.pair,
      side: row.side,
      threshold: row.threshold,
      max_usd: row.max_usd,
      share: row.share,
      platform: row.platform,
      slippage: row.slippage,
    }));

    return res.json({ status: ['success'], status_code: [200], bots });
  } catch (e: any) {
    console.log(`Error: getBots — manager: ${manager} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error fetching bots'] });
  }
});

export default router;
