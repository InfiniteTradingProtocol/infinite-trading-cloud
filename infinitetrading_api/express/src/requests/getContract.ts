/**
 * shadow/endpoints/getContract.ts — Node port of R gateway's getContract.R.
 * See getSymbol.ts for full parity notes (same pattern, inverse lookup).
 *
 * PARITY WARNING: as of 2026-09-06, the LIVE R endpoint /getContract (and
 * /getSymbol) are actually BROKEN in production — every call errors with
 * `argument is of length zero` inside is_valid_protocol(), because something in
 * the R gateway (likely reporting.R/send_request_report or a shared request
 * pre-processing step) is passing protocol="" (character(0) after some
 * transform) into a code path that reaches is_valid_protocol() even though
 * getSymbol.R/getContract.R never call basic_check() with a protocol arg
 * themselves. Confirmed live via `pm2 logs api-gateway`:
 *   <simpleError in if (!is_valid_protocol(protocol)) ...: argument is of length zero>
 * This port implements the CORRECT intended behavior (no protocol check at all,
 * matching what getContract.R actually calls: basic_check(network=network,
 * apiKey=apiKey) with no protocol/pool/wallet/pair). The parity-test script
 * must special-case these two endpoints as "known-broken baseline" rather than
 * failing the diff, until the R bug is separately fixed or these endpoints are
 * fully cut over.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat } from '../basicCheck';

const router = Router();

/**
 * @openapi
 * /getContract:
 *   get:
 *     summary: Get a token's contract address by symbol and network
 *     tags: [Tokens]
 *     parameters:
 *       - in: query
 *         name: symbol
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: The contract address, or null if not found.
 */
router.get('/getContract', async (req: Request, res: Response) => {
  const symbolRaw = String(req.query.symbol || '');
  const networkRaw = String(req.query.network || '');
  const apiKey = String(req.query.apiKey || '');

  // Mirrors R's getContract(): basic_check(network=network, apiKey=apiKey).
  const check = await basicCheck({ network: networkRaw, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const symbol = symbolRaw.toLowerCase();
  const network = networkRaw.toLowerCase();

  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [symbol, network]
    );
    if (rows.length === 0) {
      console.log(`Warning: No contract found for the given symbol: ${symbol} and network: ${network}, returning NULL`);
      return res.json(null);
    }
    return res.json(rows[0].contract);
  } catch (e: any) {
    console.log(`Error obtaining the contract for: ${symbol} and network: ${network} error: ${e.message}, returning NULL`);
    return res.json(null);
  }
});

export default router;
