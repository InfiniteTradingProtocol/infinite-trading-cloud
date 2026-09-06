/**
 * requests/approve.ts — Node port of the public /approve endpoint, previously
 * served by the R gateway (port 8003, gateway/endpoints/approve.R) which
 * proxied to plumber-api (port 8002, api.R's approveHandler ~line 176), which
 * in turn proxied to Express's own POST /approve (now renamed /approveRaw,
 * see requests/trade.ts).
 *
 * ***MONEY-ADJACENT*** — sends an on-chain ERC20 approval transaction from the
 * vault. It does not move funds itself, but a wrong approval is a real risk, so
 * validation order mirrors R exactly.
 *
 * PARITY NOTES:
 *  - Gateway layer (approve.R):
 *      * network/protocol/platform lower-cased.
 *      * basic_check(network, protocol, pool, apiKey); on fail the check is
 *        returned as-is, in jsonlite's non-auto-unboxed array wire format
 *        (verified live: {"status":["fail"],"status_code":["1000"],...}).
 *      * platform defaulted to "odos" in R. odos is DEPRECATED (see
 *        utils/parseDapp.ts) so the default is now DEFAULT_PLATFORM ("auto");
 *        passing platform=odos still works and resolves to automatic routing.
 *  - Inner layer (api.R approveHandler):
 *      * symbol aliasing BTC->WBTC, USD->USDC, ETH->WETH, MATIC/POL->WMATIC.
 *      * isValidApiKey(network, protocol, pool, apiKey) DB check ->
 *        401 "The API Key is invalid or it has not linked to the specified pool".
 *      * asset resolution: a 0x address passes through (and its symbol is
 *        looked up for the BULL/BEAR test below); a symbol is resolved to a
 *        contract via the coins/networks tables. Unresolvable ->
 *        400 "Unsupported asset for the specified network and protocol".
 *      * leveraged Toros tokens (symbol containing BULL/BEAR) force
 *        platform="toros".
 *      * up to 3 attempts against the raw endpoint, no retry on a <500 status,
 *        backoff 0.5s then 1s.
 *      * success -> {status:"success",status_code:200,message:"Asset approved"};
 *        any other outcome -> {status:"fail",status_code:400,
 *        message:"Approve failed, try again or contact support"} (R deliberately
 *        does NOT surface the underlying error to the caller).
 *  - R also computed pool_comp() here, but its only consumer (the
 *    "Enable <symbol> on the dHEDGE vault first." guard) is commented out in
 *    api.R, so the call is pure dead weight and is intentionally NOT ported.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';
import { DEFAULT_PLATFORM } from '../utils/parseDapp';
import { notifyApiActivity, maskApiKey } from '../utils/telegram';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

/** R's approveHandler symbol aliasing (api.R lines 178-181). */
function aliasSymbol(sym: string): string {
  if (sym === 'BTC') return 'WBTC';
  if (sym === 'USD') return 'USDC';
  if (sym === 'ETH') return 'WETH';
  if (sym === 'MATIC' || sym === 'POL') return 'WMATIC';
  return sym;
}

/** Port of R's isValidApiKey(network, protocol, pool, apiKey) (api/db.R ~563). */
async function isValidApiKeyForPool(network: string, protocol: string, pool: string, apiKey: string): Promise<boolean> {
  try {
    const rows = await dbQuery(
      'SELECT 1 FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ? AND token = ? LIMIT 1',
      [network, protocol, pool, apiKey]
    );
    return rows.length > 0;
  } catch (e: any) {
    console.log('Error: isValidApiKey:', e.message);
    return false;
  }
}

async function getContractForSymbol(symbol: string, network: string): Promise<string | null> {
  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [symbol.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].contract) : null;
  } catch {
    return null;
  }
}

/** Port of R's get_symbol(contract, network); returns "Unknown" when unmapped. */
async function getSymbolForContract(contract: string, network: string): Promise<string> {
  try {
    const rows = await dbQuery(
      'SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?',
      [contract.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].symbol) : 'Unknown';
  } catch {
    return 'Unknown';
  }
}

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

/**
 * @openapi
 * /approve:
 *   post:
 *     summary: Approve an asset for trading or lending/borrowing from a Chamber vault
 *     description: >
 *       Sends an ERC20 approval from the vault so the given asset can be used by
 *       the specified platform (DEX or lending market). To go short you must also
 *       approve BTC1XBEAR / ETH1XBEAR (Optimism and Arbitrum only).
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: asset
 *         required: true
 *         description: Symbol (e.g. USDC) or contract address.
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, enum: [dhedge, chamber, defund], default: dhedge }
 *       - in: query
 *         name: platform
 *         description: >
 *           Execution venue for the approval (e.g. aavev3, uniswapv3, kyberswap).
 *           Defaults to automatic routing. The legacy value "odos" is still
 *           accepted but is deprecated and maps to automatic routing.
 *         schema: { type: string, enum: [auto, uniswapV3, velodrome, velodromecl, aerodrome, aerodromecl, pancakecl, quickswap, kyberswap, cowswap, pendle, aavev3, compoundv3, fluid, lyra, hyperliquid], default: auto }
 *     responses:
 *       200:
 *         description: Approval result.
 */
async function handleApprove(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };
  const network = String(q.network || '').toLowerCase();
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  let platform = String(q.platform || DEFAULT_PLATFORM).toLowerCase();
  const apiKey = String(q.apiKey || '');
  const pool = String(q.pool || '');
  // R's gateway takes `asset` from the query string only, but Express's raw
  // /approve has always taken it in the JSON body and internal strategy scripts
  // call it that way — accept both so no internal caller can break.
  let asset = String(q.asset || '');

  // === Gateway layer: basic_check ===
  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  // === Inner layer: symbol aliasing ===
  asset = aliasSymbol(asset);

  // === Inner layer: isValidApiKey DB check (gas wallet linked to pool) ===
  const validForPool = await isValidApiKeyForPool(network, protocol, pool.toLowerCase(), apiKey);
  if (!validForPool) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The API Key is invalid or it has not linked to the specified pool'] });
  }

  // === Inner layer: asset -> contract + symbol resolution ===
  let assetContract: string | null;
  let symbol: string;
  if (isValidEthereumAddress(asset)) {
    assetContract = asset;
    symbol = await getSymbolForContract(asset, network);
  } else {
    assetContract = await getContractForSymbol(asset, network);
    symbol = asset;
  }
  if (!assetContract) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Unsupported asset for the specified network and protocol'] });
  }

  // === Inner layer: leveraged Toros tokens must be approved on Toros ===
  if (/BULL/i.test(symbol) || /BEAR/i.test(symbol)) {
    platform = 'toros';
  }

  const params = new URLSearchParams();
  params.set('network', network);
  params.set('apiKey', apiKey);
  params.set('pool', pool);
  params.set('platform', platform);

  const masked = maskApiKey(apiKey);
  const url = `${EXPRESS_BASE}approveRaw?${params.toString()}`;
  console.log(`approve -> ${url.replace(apiKey, masked)} / asset: ${asset} / contract: ${assetContract}`);

  // === Inner layer: up to 3 attempts, no retry on non-5xx ===
  let lastStatus = 0;
  let lastBody: any = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ asset: assetContract }),
      });
      lastStatus = resp.status;
      lastBody = await resp.json().catch(() => ({}));
      if (resp.status < 500) break;
    } catch (e: any) {
      lastStatus = 0;
      lastBody = { msg: e.message };
    }
    if (attempt < 3) await sleep(Math.min(0.5 * Math.pow(2, attempt - 1), 1.0) * 1000);
  }

  const ok = lastStatus === 200;
  const result = ok
    ? { status: ['success'], status_code: [200], message: ['Asset approved'] }
    : { status: ['fail'], status_code: [400], message: ['Approve failed, try again or contact support'] };

  notifyApiActivity({
    status: ok ? 'success' : 'fail',
    endpoint: 'approve',
    apiKey,
    fields: { pool, protocol, network, asset, symbol, platform },
    response: ok ? 'Asset approved' : lastBody,
  });

  return res.json(result);
}

router.post('/approve', handleApprove);

export default router;
