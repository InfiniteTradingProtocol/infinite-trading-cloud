/**
 * shadow/endpoints/getGasWalletPools.ts — Node port of R gateway's
 * getGasWalletPools.R (proxies to plumber-api port 8002's
 * getGasWalletPoolsHandler in src/api/api.R).
 *
 * PARITY NOTES:
 *  - Uses the "frontend" literal apiKey scheme (same family as
 *    getTotalYield/getAllYields/getCandles/getTicks) — confirmed in source:
 *    `if (apiKey=="frontend") return(getWalletPools(...)); list(fail 401)`.
 *  - protocol/network/wallet are lower-cased before use (R:
 *    `protocol = tolower(protocol); network=tolower(network); wallet = tolower(wallet)`).
 *  - network validation: if network != "all", must pass is_valid_network()
 *    (checked BEFORE the protocol check, confirmed from source order).
 *  - protocol validation: if protocol != "dhedge", must pass
 *    is_valid_protocol() (checked AFTER the network check).
 *  - Query (src/api/db.R's getWalletPools): for network="all", expands to
 *    ["optimism","base","arbitrum","polygon"] (NOT ethereum — confirmed from
 *    source, this 4-network list is hardcoded and differs from the 5-network
 *    list used elsewhere for gas balances).
 *      SELECT network, pool, is_active FROM gas_wallets
 *      WHERE protocol = ? AND network IN (...) AND wallet_address = ?
 *        AND pool IS NOT NULL
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../../db';

const router = Router();

const VALID_NETWORKS = ['ethereum', 'polygon', 'optimism', 'arbitrum', 'base'];

function isValidNetworkName(network: string): boolean {
  return VALID_NETWORKS.includes(network);
}

// isValidProtocol/is_valid_protocol was found to be genuinely broken in R
// live testing during getSymbol/getContract porting (crashes on zero-length
// arg). getGasWalletPoolsHandler only reaches this check for protocol !=
// "dhedge", which isn't exercised by any currently-known caller — implements
// the intended check (protocol must be a known supported protocol string).
function isValidProtocolName(protocol: string): boolean {
  return ['dhedge'].includes(protocol);
}

router.get('/getGasWalletPools', async (req: Request, res: Response) => {
  const apiKey = String(req.query.apiKey || '');
  const protocol = String(req.query.protocol || '').toLowerCase();
  const network = String(req.query.network || '').toLowerCase();
  const wallet = String(req.query.wallet || '').toLowerCase();

  if (network !== 'all' && !isValidNetworkName(network)) {
    return res.json({ status: ['fail'], status_code: ['1000'], message: ['Unrecognized network'] });
  }
  if (protocol !== 'dhedge' && !isValidProtocolName(protocol)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Unrecognized protocol'] });
  }
  if (apiKey !== 'frontend') {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid API Key'] });
  }

  try {
    const networks = network === 'all' ? ['optimism', 'base', 'arbitrum', 'polygon'] : [network];
    const placeholders = networks.map(() => '?').join(',');
    const rows = await dbQuery(
      `SELECT network, pool, is_active FROM gas_wallets WHERE protocol = ? AND network IN (${placeholders}) AND wallet_address = ? AND pool IS NOT NULL`,
      [protocol, ...networks, wallet]
    );
    return res.json({ status: ['success'], status_code: [200], message: rows });
  } catch (e: any) {
    console.log(`Error in getWalletPools: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error getting pools for wallet'] });
  }
});

export default router;
