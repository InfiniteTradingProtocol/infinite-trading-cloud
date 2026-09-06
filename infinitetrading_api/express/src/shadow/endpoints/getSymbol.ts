/**
 * shadow/endpoints/getSymbol.ts — Node port of R gateway's getSymbol.R.
 *
 * PARITY NOTES (see R source: infinitetrading/src/api/gateway/endpoints/getSymbol.R):
 *  - apiKey IS required and validated via basic_check(network, apiKey) — confirmed
 *    live: passing an invalid network returns {status:"fail", status_code:"1000",
 *    message:"Unrecognized network"} correctly (this branch works fine in R; only
 *    the *protocol* check path is buggy, and getSymbol.R never triggers it).
 *  - Both contract and network are lower-cased before lookup, matching R.
 *  - Query: SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id
 *           WHERE c.contract = ? AND n.name = ?
 *  - Returns NULL (JSON `null`) if not found — matches R's `NULL` return, which
 *    plumber serializes as JSON null.
 *  - On DB error, R logs and returns NULL rather than throwing — replicated below.
 *
 * PARITY WARNING: as of 2026-09-06, the LIVE R /getSymbol endpoint is actually
 * BROKEN in production (returns generic 500 for every request). Confirmed via
 * `pm2 logs api-gateway`:
 *   <simpleError in if (!is_valid_protocol(protocol)) ...: argument is of length zero>
 * even though getSymbol.R never passes `protocol` to basic_check(). This port
 * implements the CORRECT intended behavior. See getContract.ts for the same
 * issue on that sibling endpoint. The parity-test script treats these two as
 * "known-broken baseline" rather than failing the diff.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../../db';
import { basicCheck, toRWireFormat } from '../basicCheck';

const router = Router();

/**
 * @openapi
 * /getSymbol:
 *   get:
 *     summary: Get a token's symbol by contract address and network
 *     tags: [Tokens]
 *     parameters:
 *       - in: query
 *         name: contract
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: The token symbol, or null if not found.
 */
router.get('/getSymbol', async (req: Request, res: Response) => {
  const contractRaw = String(req.query.contract || '');
  const networkRaw = String(req.query.network || '');
  const apiKey = String(req.query.apiKey || '');

  // Mirrors R's getSymbol(): basic_check(network=network, apiKey=apiKey) — no
  // protocol/pool/wallet/pair passed, so only network + apiKey are validated.
  const check = await basicCheck({ network: networkRaw, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const contract = contractRaw.toLowerCase();
  const network = networkRaw.toLowerCase();

  try {
    const rows = await dbQuery(
      'SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?',
      [contract, network]
    );
    if (rows.length === 0) {
      console.log(`No symbol found for the given contract: ${contract} and network: ${network}, returning NULL`);
      return res.json(null);
    }
    return res.json(rows[0].symbol);
  } catch (e: any) {
    console.log(`Error obtaining the symbol for: ${contract} and network: ${network} error: ${e.message}, returning NULL`);
    return res.json(null);
  }
});

export default router;
