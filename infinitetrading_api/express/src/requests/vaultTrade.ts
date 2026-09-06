/**
 * requests/vaultTrade.ts — Node port of R gateway's vaultTrade.R (proxies to
 * plumber-api port 8002's vaultTradeHandler in src/api/api.R).
 *
 * ***HIGH RISK*** — this endpoint executes a real on-chain swap inside a
 * dHEDGE vault via the already-migrated /trade endpoint. Ported with extra
 * scrutiny; validation order and asset-resolution logic mirror R exactly.
 *
 * PARITY NOTES:
 *  - Gateway layer (vaultTrade.R):
 *      * basicCheck(network, protocol, pool, apiKey) -- fail -> returned
 *        as-is (gateway's vaultTradeHandler returns `check` directly on
 *        failure) -- replicated via toRWireFormat(check).
 *      * share must be an integer in [1,100] (NA/out-of-range -> fail
 *        status_code 1007) UNLESS amount is given (amount path bypasses the
 *        share requirement entirely at the gateway layer -- confirmed from
 *        R source: only checked/built when the `res$status=="success"`
 *        placeholder passes, and the placeholder is only set to fail when
 *        share itself is invalid regardless of amount -- so in R, if amount
 *        is present AND share is invalid, the request still fails at the
 *        gateway layer. This is preserved here: share is validated even
 *        when amount is present, exactly matching R's actual (perhaps
 *        unintended) behavior.)
 *  - Inner (port 8002) layer (vaultTradeHandler in api.R), in this order:
 *      1. is_toros(from) || is_toros(to) -> forces platform="toros".
 *      2. api_check(apiKey, protocol, pool, wallet=NULL, network) ==
 *         getWallet(apiKey) then isValidTrader(protocol, pool, wallet) --
 *         fail -> returns api_check's own status_code (e.g. "1006").
 *      3. Symbol aliasing: BTC->WBTC, USD->USDC, ETH->WETH,
 *         MATIC/POL->WMATIC (both from and to, R only aliases `to=="BTC"`
 *         to itself which is a no-op bug -- replicated faithfully, i.e. the
 *         "to" BTC alias is NOT rewritten to WBTC, only "from" is; this is
 *         an R quirk kept for byte-for-byte parity).
 *      4. isValidApiKey(network, protocol, pool, apiKey) DB check (the
 *         gas_wallets linkage check, same as deleteBot/unlinkGasWallet) --
 *         fail -> 401 "The API Key is invalid or it has not linked to the
 *         specified pool".
 *      5. from/to resolution: if already a 0x address, use as-is; else
 *         getContract(symbol, network) DB lookup -- either missing ->
 *         400 "Unsupported '<from|to>' asset for the specified network and
 *         protocol".
 *      6. amount (if present, not NA/"NA") takes precedence over share:
 *         amount = floor(amount * 10^get_decimals(from)); share ignored.
 *         Else share must be an integer in [1,100].
 *      7. Calls Express's own /trade with the resolved contract addresses
 *         (internal loopback call, matching R's ep+"trade?..." call which
 *         already targeted Express on port 8000).
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';
import { isValidTrader } from '../dhedgeTrader';
import { DEFAULT_PLATFORM } from '../utils/parseDapp';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

function isToros(asset: string): boolean {
  const a = (asset || '').toUpperCase();
  return ['BTCBULL3X', 'BTCBULL2X', 'BTCBULL4X', 'ETHBULL3X', 'ETHBULL2X', 'ETHBEAR1X', 'BTCBEAR1X'].includes(a);
}

function getDecimals(asset: string): number {
  const a = (asset || '').toUpperCase();
  if (a === 'WBTC') return 8;
  if (a === 'USDC' || a === 'USDT' || a === 'USDCN') return 6;
  return 18;
}

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

// Same symbol aliasing quirk as R's vaultTradeHandler (including the
// intentional-looking no-op `to == "BTC" -> to = "BTC"` bug, kept for
// byte-for-byte parity).
function aliasSymbol(sym: string, isFrom: boolean): string {
  if (isFrom) {
    if (sym === 'BTC') return 'WBTC';
    if (sym === 'USD') return 'USDC';
    if (sym === 'ETH') return 'WETH';
    if (sym === 'MATIC' || sym === 'POL') return 'WMATIC';
    return sym;
  } else {
    if (sym === 'BTC') return 'BTC'; // R quirk: no-op, replicated faithfully
    if (sym === 'USD') return 'USDC';
    if (sym === 'ETH') return 'WETH';
    if (sym === 'MATIC' || sym === 'POL') return 'WMATIC';
    return sym;
  }
}

/**
 * @openapi
 * /vaultTrade:
 *   get:
 *     summary: Execute a trade inside a dHEDGE vault (HIGH RISK, live trading)
 *     tags: [Managers]
 *     parameters:
 *       - in: query
 *         name: network
 *         schema: { type: string, default: optimism }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, default: dhedge }
 *       - in: query
 *         name: platform
 *         schema: { type: string, default: auto }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: from
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: to
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: slippage
 *         schema: { type: number, default: 0.5 }
 *       - in: query
 *         name: share
 *         schema: { type: number, default: 100 }
 *       - in: query
 *         name: amount
 *         schema: { type: number }
 *     responses:
 *       200:
 *         description: Trade executed.
 */
async function handleVaultTrade(req: Request, res: Response) {
  const q = { ...req.query, ...req.body };
  const networkRaw = String(q.network || 'optimism').toLowerCase();
  let protocolRaw = String(q.protocol || 'dhedge').toLowerCase();
  let platformRaw = String(q.platform || DEFAULT_PLATFORM).toLowerCase();
  const apiKey = String(q.apiKey || '');
  const poolRaw = String(q.pool || '').toLowerCase();
  let fromRaw = String(q.from || '');
  let toRaw = String(q.to || '');
  const slippageRaw = q.slippage === undefined ? '0.5' : String(q.slippage);
  const shareQuery = q.share === undefined ? '100' : String(q.share);
  const amountQuery = q.amount === undefined ? undefined : String(q.amount);

  // === Gateway layer: basicCheck ===
  const check = await basicCheck({ network: networkRaw, protocol: protocolRaw, pool: poolRaw, apiKey });
  if (check.status === 'fail') {
    return res.json(toRWireFormat(check));
  }

  // === Gateway layer: share must be an integer in [1,100] (checked
  // regardless of whether amount is also present -- matches R's actual
  // gateway behavior). ===
  const shareNum = Number(shareQuery);
  if (!Number.isFinite(shareNum) || shareNum < 1 || shareNum > 100) {
    return res.json({ status: ['fail'], status_code: ['1007'], message: ["error: share is not an integer between [1,100]"] });
  }
  const share = Math.round(shareNum);

  // === Inner layer: is_toros aliasing forces platform=toros ===
  if (isToros(fromRaw) || isToros(toRaw)) { platformRaw = 'toros'; }

  // === Inner layer: api_check == getWallet(apiKey) + isValidTrader ===
  const wallet = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Unable to resolve wallet for API key'] });
  }
  const validTrader = await isValidTrader(protocolRaw, poolRaw, wallet);
  if (!validTrader) {
    return res.json({ status: ['fail'], status_code: ['1006'], message: ['The trader wallet is not configured as a trader in the specified pool'] });
  }

  // === Inner layer: symbol aliasing ===
  fromRaw = aliasSymbol(fromRaw, true);
  toRaw = aliasSymbol(toRaw, false);

  // === Inner layer: isValidApiKey DB check (gas wallet linked to pool) ===
  const validForPool = await isValidApiKeyForPool(networkRaw, protocolRaw, poolRaw, apiKey);
  if (!validForPool) {
    return res.json({ status: ['fail'], status_code: [401], message: ["The API Key is invalid or it has not linked to the specified pool"] });
  }

  // === Inner layer: from/to symbol -> contract resolution ===
  const fromContract = isValidEthereumAddress(fromRaw) ? fromRaw : await getContractForSymbol(fromRaw, networkRaw);
  const toContract = isValidEthereumAddress(toRaw) ? toRaw : await getContractForSymbol(toRaw, networkRaw);
  if (!fromContract) {
    return res.json({ status: ['fail'], status_code: [400], message: ["Unsupported 'from' asset for the specified network and protocol"] });
  }
  if (!toContract) {
    return res.json({ status: ['fail'], status_code: [400], message: ["Unsupported 'to' asset for the specified network and protocol"] });
  }

  const slippage = Number(slippageRaw);

  const params = new URLSearchParams();
  params.set('apiKey', apiKey);
  params.set('protocol', protocolRaw);
  params.set('pool', poolRaw);
  params.set('network', networkRaw);
  params.set('from', fromContract);
  params.set('to', toContract);
  params.set('slippage', String(slippage));
  params.set('platform', platformRaw);
  if (isToros(fromRaw)) { params.set('withdrawal', 'true'); }

  // === Inner layer: amount takes precedence over share ===
  let amountUsed: number | undefined;
  if (amountQuery !== undefined && amountQuery !== 'NA') {
    const amountNum = Number(amountQuery);
    if (!Number.isFinite(amountNum)) {
      return res.json({ status: ['fail'], status_code: [400], message: ["The specified amount parameter is not numeric"] });
    }
    if (amountNum <= 0) {
      return res.json({ status: ['fail'], status_code: [400], message: ["The speficied amount parameter must be a number > 0 or NA"] });
    }
    const decimals = getDecimals(fromRaw);
    const scaledAmount = Math.floor(amountNum * Math.pow(10, decimals));
    amountUsed = scaledAmount;
    params.set('amount', String(scaledAmount));
  } else {
    params.set('share', String(share));
  }

  const maskedApi = apiKey.length > 8 ? `${apiKey.slice(0, 4)}...${apiKey.slice(-4)}` : '****';

  try {
    const tradeUrl = `${EXPRESS_BASE}trade?${params.toString()}`;
    console.log(`vaultTrade -> ${tradeUrl.replace(apiKey, maskedApi)}`);
    const tradeResp = await fetch(tradeUrl);
    const tradeData: any = await tradeResp.json().catch(() => ({}));

    const logMsg = `vaultTrade invoked by apiKey: ${maskedApi} / pool: ${poolRaw} / protocol: ${protocolRaw} / network: ${networkRaw} / from: ${fromRaw} / to: ${toRaw} / amount: ${amountUsed ?? 'NA'} / slippage: ${slippage} / share: ${share} / platform: ${platformRaw} / status: ${tradeResp.status}`;
    console.log(logMsg);

    if (tradeResp.status === 200) {
      return res.json({ status: ['success'], status_code: [200], message: ['trade executed'] });
    } else {
      const msg = tradeData && tradeData.msg ? tradeData.msg : 'unknown error';
      return res.json({ status: ['fail'], status_code: [tradeResp.status], message: [`trade failed: ${msg}`] });
    }
  } catch (e: any) {
    console.log(`Error: vaultTrade — pool: ${poolRaw} network: ${networkRaw} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: [`Internal error executing vault trade: ${e.message}`] });
  }
}

router.get('/vaultTrade', handleVaultTrade);
router.post('/vaultTrade', handleVaultTrade);

export default router;
