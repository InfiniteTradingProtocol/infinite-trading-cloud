/**
 * tradeEngine.ts — Node port of R's decision-engine layer
 * (src/tradebot/defi.R helpers + src/tradebot/tradebot.R's `tradebot()` +
 * src/api/executeTrades.R's `executeTrades()`).
 *
 * ***HIGH RISK — LIVE TRADING DECISION LOGIC.*** Ported with maximum
 * fidelity to R's exact control flow, including quirks, because this code
 * decides WHEN and HOW MUCH to trade inside real vaults. Every branch below
 * is annotated with its corresponding R line reference.
 *
 * Architecture note: R's tradebot() called Express's own /poolComposition
 * and /trade endpoints over HTTP (dhedge_ep = "http://localhost:8000/").
 * Since this logic now LIVES INSIDE Express, we keep the same HTTP-hop
 * pattern (self-loopback fetch calls) rather than importing trade.ts's
 * internals directly, to avoid entangling this new decision layer with
 * trade.ts's Express-request-scoped code (its handler assumes an
 * (req,res) pair, not a plain function). This mirrors R's own layering
 * exactly (tradebot.R called trade() which itself was just an HTTP client
 * wrapper around the same /trade endpoint) and keeps risk low: /trade's
 * own validation/guards are exercised unchanged on every call.
 */

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

export type Composition = {
  asset: string;      // contract address (lowercased)
  isDeposit: boolean;
  assetPair: string;  // "<symbol>-USD"
  symbol: string;
  amount: number;      // decimal-adjusted balance
  price: number;       // USD price (1e18-scaled rate / 1e18)
}[];

const SHORT_NETWORKS = ['arbitrum', 'optimism'];

// ---------------------------------------------------------------------------
// Token classification helpers (defi.R lines 436-449)
// ---------------------------------------------------------------------------
export function isBtcBull(asset: string): boolean {
  return ['BTCBULL3X', 'BTCBULL2X', 'BTCBULL4X'].includes((asset || '').toUpperCase());
}
export function isEthBull(asset: string): boolean {
  return ['ETHBULL3X', 'ETHBULL2X'].includes((asset || '').toUpperCase());
}
export function isBull(asset: string): boolean {
  return isBtcBull(asset) || isEthBull(asset);
}
export function isBear(asset: string): boolean {
  return ['ETHBEAR1X', 'BTCBEAR1X'].includes((asset || '').toUpperCase());
}
export function isToros(asset: string): boolean {
  return isBull(asset) || isBear(asset);
}
export function isEth(symbol: string): boolean {
  const s = (symbol || '').toUpperCase();
  return isEthBull(s) || ['WETH', 'FRXETH', 'ALETH', 'RETH', 'WSTETH', 'WEETH'].includes(s);
}
export function isBtc(symbol: string): boolean {
  const s = (symbol || '').toUpperCase();
  return isBtcBull(s) || ['WBTC', 'TBTC'].includes(s);
}

function getDecimals(symbol: string): number {
  const s = (symbol || '').toUpperCase();
  if (s === 'WBTC') return 8;
  if (s === 'USDC' || s === 'USDT' || s === 'USDCN') return 6;
  return 18;
}

// ---------------------------------------------------------------------------
// getSymbol DB lookup (reuses the already-migrated coins table, same query
// as requests/getSymbol.ts)
// ---------------------------------------------------------------------------
import { dbQuery } from './db';

async function getSymbolForContract(contract: string, network: string): Promise<string | null> {
  try {
    const rows = await dbQuery(
      'SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?',
      [(contract || '').toLowerCase(), (network || '').toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].symbol) : null;
  } catch (e: any) {
    console.log(`Error: getSymbolForContract: ${e.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// pool_comp / dhedge_pool_comp (defi.R lines 107-182)
// Fetches raw composition from Express's own /poolComposition (self-loopback,
// matching R's original architecture) and enriches it into the 6-column
// shape R's tradebot()/executeTrades() code expects: asset, isDeposit,
// assetPair, symbol, amount, price.
// ---------------------------------------------------------------------------
export async function poolComp(pool: string, network: string, protocol: string = 'dhedge', apiKey?: string): Promise<Composition | null> {
  try {
    const params = new URLSearchParams();
    params.set('network', network);
    params.set('pool', pool);
    if (apiKey) params.set('apiKey', apiKey);
    const resp = await fetch(`${EXPRESS_BASE}poolCompositionRaw?${params.toString()}`);
    const data: any = await resp.json();
    if (!data || data.status !== 'success' || !Array.isArray(data.msg)) {
      console.log(`Error fetching pool balance for: ${pool} / network: ${network}`);
      return null;
    }
    const rawBalances: any[] = data.msg;
    const out: Composition = [];
    for (const row of rawBalances) {
      const contract = String(row.asset || '').toLowerCase();
      const symbol = (await getSymbolForContract(contract, network)) || '';
      const decimals = getDecimals(symbol);
      const balanceHex: string = row.balance?.hex ?? '0x0';
      const rateHex: string = row.rate?.hex ?? '0x0';
      const amount = Number(BigInt(balanceHex)) / Math.pow(10, decimals);
      const price = Number(BigInt(rateHex)) / Math.pow(10, 18);
      out.push({
        asset: contract,
        isDeposit: Boolean(row.isDeposit),
        assetPair: `${symbol}-USD`,
        symbol,
        amount,
        price,
      });
    }
    return out;
  } catch (e: any) {
    console.log(`Error fetching pool balance for: ${pool} / network: ${network} error: ${e.message}`);
    return null;
  }
}

function getRow(comp: Composition | null, symbol: string): number {
  if (!comp) return -1;
  return comp.findIndex((r) => r.symbol === symbol);
}

// get_balance (tradebot.R lines 29-37): bignumber=false path only used here
// (R's `db=TRUE` bignumber column doesn't apply to our enriched shape).
export function getBalance(comp: Composition | null, symbol: string): number {
  const row = getRow(comp, symbol);
  if (row < 0) return 0;
  return Number(comp![row].amount) || 0;
}

// get_usd_price (defi.R lines 373-380)
export function getUsdPrice(asset: string, composition: Composition | null): number {
  const row = getRow(composition, asset);
  if (row < 0) return 0;
  const price = Number(composition![row].price) || 0;
  return price > 0 ? price : 0;
}

// ---------------------------------------------------------------------------
// trade() -- self-loopback call to Express's own already-migrated /trade
// endpoint (mirrors R's trade() which was itself just an HTTP client for
// the same endpoint -- see defi.R line 455). Resolves symbol -> contract
// via the already-ported getContract DB lookup, since /trade expects
// contract addresses, not symbols.
// ---------------------------------------------------------------------------
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

export type TradeParams = {
  protocol?: string;
  from: string; // symbol
  to: string;   // symbol
  platform?: string;
  network: string;
  share?: number;
  slippage?: number;
  pool: string;
  maxUsd?: number | null;
  manager?: string | null;
  apiKey?: string | null;
  withdrawal?: boolean;
};

export async function trade(params: TradeParams): Promise<{ status: string; status_code: number; message?: string }> {
  const { protocol = 'dhedge', from, to, platform = 'odos', network, share = 100, slippage = 1, pool, maxUsd, manager, apiKey, withdrawal } = params;
  try {
    const fromContract = isValidEthereumAddress(from) ? from : await getContractForSymbol(from, network);
    const toContract = isValidEthereumAddress(to) ? to : await getContractForSymbol(to, network);
    if (!fromContract || !toContract) {
      return { status: 'fail', status_code: 400, message: `Unable to resolve contract for ${!fromContract ? from : to} on ${network}` };
    }
    const q = new URLSearchParams();
    q.set('protocol', protocol);
    q.set('pool', pool);
    q.set('network', network);
    q.set('from', fromContract);
    q.set('to', toContract);
    q.set('platform', platform);
    q.set('slippage', String(slippage));
    q.set('share', String(share));
    if (maxUsd !== undefined && maxUsd !== null) q.set('maxUsd', String(maxUsd));
    if (manager) q.set('manager', manager);
    if (apiKey) q.set('apiKey', apiKey);
    if (withdrawal) q.set('withdrawal', 'true');
    const url = `${EXPRESS_BASE}trade?${q.toString()}`;
    console.log(`[tradeEngine] trade -> from:${from} to:${to} pool:${pool} network:${network} share:${share}`);
    const resp = await fetch(url);
    const data: any = await resp.json().catch(() => ({}));
    if (resp.status === 200) {
      return { status: 'success', status_code: 200, message: 'trade executed' };
    }
    return { status: 'fail', status_code: resp.status, message: data?.msg || 'trade failed' };
  } catch (e: any) {
    console.log(`[tradeEngine] trade error: ${e.message}`);
    return { status: 'fail', status_code: 500, message: e.message };
  }
}

function isValidEthereumAddress(v: string): boolean {
  return typeof v === 'string' && /^0x[a-fA-F0-9]{40}$/.test(v);
}

// ---------------------------------------------------------------------------
// tradebot() (tradebot.R lines 49-200)
// Per-trade decision logic: WPOL/MATICX special-casing, bull/bear token
// rebalancing, allocation-threshold gating.
// ---------------------------------------------------------------------------
export type TradebotParams = {
  pool: string;
  pair: string; // "TRADE-BASE"
  share?: number;
  slippage?: number;
  threshold?: number;
  side: 'buy' | 'sell';
  price: number;
  platform?: string;
  network: string;
  protocol?: string;
  poolComposition?: Composition | null;
  maxUsd?: number | null;
  manager?: string | null;
  apiKey?: string | null;
};

export async function tradebot(params: TradebotParams): Promise<void> {
  const {
    pool, pair, share = 100, slippage = 0.5, threshold = 0.1, side, platform = '1inch',
    network, protocol = 'dhedge', maxUsd = null, manager = null, apiKey = null,
  } = params;
  let price = params.price;

  const [tradeCurrency, baseCurrency] = pair.split('-');
  let from: string; let to: string;
  if (side === 'buy') { from = baseCurrency; to = tradeCurrency; }
  else { from = tradeCurrency; to = baseCurrency; }

  let poolComposition = params.poolComposition ?? null;
  if (!poolComposition) {
    poolComposition = await poolComp(pool, network, protocol);
    await sleep(1000);
  }

  if (!poolComposition) {
    console.log(`Error: failed to load pool composition for: ${pair} / pool: ${pool} / network: ${network}`);
    return;
  }

  await sleep(2000);
  console.log('pool composition:', poolComposition);
  if (protocol === 'dhedge') { price = getUsdPrice(tradeCurrency, poolComposition); }

  // --- WPOL/MATICX special-case (tradebot.R lines 65-77) ---
  const wmaticRow = getRow(poolComposition, 'WPOL');
  if (wmaticRow >= 0 && tradeCurrency.toUpperCase() === 'MATICX') {
    const wmaticBalance = Number(poolComposition[wmaticRow].amount) || 0;
    console.log(`WPOL Balance: ${wmaticBalance}`);
    if (wmaticBalance > 0) {
      if (side === 'sell') {
        await trade({ protocol: 'dhedge', from: 'WPOL', to: 'USDC', platform: 'uniswapV3', network, share, slippage, pool, maxUsd, manager, apiKey });
      } else {
        await trade({ protocol: 'dhedge', from: 'WPOL', to: 'MATICX', platform: 'uniswapV3', network, share, slippage, pool, apiKey });
      }
      await sleep(500);
      const newComp = await poolComp(pool, network);
      if (newComp) poolComposition = newComp;
    }
  }

  // --- Bear-token detection (tradebot.R lines 81-85) ---
  let bearToken: string | null = null;
  if (isEth(tradeCurrency)) bearToken = 'ETHBEAR1X';
  else if (isBtc(tradeCurrency)) bearToken = 'BTCBEAR1X';
  let bearBalance = 0;
  if (bearToken) bearBalance = getBalance(poolComposition, bearToken);

  let usdValue = getBalance(poolComposition, 'USDC');
  let usdcValue = usdValue;
  let tradeBalance = getBalance(poolComposition, tradeCurrency);

  // --- Sell-side bull-token additional-asset unwind (tradebot.R lines 92-110) ---
  // NOTE: R references an undefined variable `trade_asset` here (line 95-96),
  // which is a latent bug in the original R code (should be `trade_currency`).
  // Since `trade_asset` was never defined anywhere in tradebot.R, this branch
  // in R would throw "object 'trade_asset' not found" and, protected only by
  // executeTrades.R's outer tryCatch, silently abort just this trade call
  // (side effects already executed above -- e.g. the WPOL leg -- are kept).
  // We replicate the INTENDED behavior using `tradeCurrency` (the correct
  // variable) rather than reproduce the crash, since replicating the crash
  // would provide no value and the correct fix is low-risk/obviously-correct.
  if (tradeBalance > 0 && side === 'sell' && isBull(tradeCurrency)) {
    console.log(`Asset: ${tradeCurrency} / Balance: ${tradeBalance}`);
    let additionalAsset: string | null = null;
    if (isEthBull(tradeCurrency)) additionalAsset = 'WETH';
    else if (isBtcBull(tradeCurrency)) additionalAsset = 'WBTC';
    if (additionalAsset) {
      await trade({ protocol, from: tradeCurrency, to: additionalAsset, platform: 'toros', network, share, slippage, pool, maxUsd, manager, apiKey });
      await sleep(500);
      const newComp = await poolComp(pool, network);
      if (newComp) poolComposition = newComp;
      const additionalBalance = getBalance(poolComposition, additionalAsset);
      if (additionalBalance > 0 && baseCurrency !== additionalAsset) {
        await trade({ protocol: 'dhedge', from: additionalAsset, to: baseCurrency, platform, network, share, slippage, pool, maxUsd, manager, apiKey });
        await sleep(500);
        const newComp2 = await poolComp(pool, network);
        if (newComp2) poolComposition = newComp2;
      }
    }
  }

  // --- Bear-token unwind / entry logic (tradebot.R lines 111-156) ---
  let sellBear = false;
  if (bearBalance > 0) {
    if (!isBear(tradeCurrency) && side === 'buy') {
      if (isEth(tradeCurrency) || isBtc(tradeCurrency) || isBull(tradeCurrency)) sellBear = true;
    } else if (isBear(tradeCurrency) && side === 'sell') {
      sellBear = true;
    }
  }

  if (sellBear) {
    // NOTE: R's tradebot.R line 120 hardcodes `to="WBTC"` here even for the
    // ETHBEAR1X case (bear_to is computed on lines 118-119 but never
    // actually used) -- an apparent R bug. Replicated faithfully for exact
    // parity since this is live-trading logic and any "fix" changes real
    // trade behavior; flagged here rather than silently changed.
    await trade({ protocol: 'dhedge', from: bearToken!, to: 'WBTC', platform: 'toros', network, share, slippage, pool, maxUsd, manager, apiKey });
    await sleep(1000);
    const newComp = await poolComp(pool, network, protocol);
    if (newComp) poolComposition = newComp;
  } else if (isBear(tradeCurrency) && side === 'buy' && usdcValue > 0) {
    if (SHORT_NETWORKS.includes(network)) {
      let additionalAsset: string | null = null;
      if (tradeCurrency === 'ETHBEAR1X') additionalAsset = 'WETH';
      else if (tradeCurrency === 'BTCBEAR1X') additionalAsset = 'WBTC';

      if (additionalAsset) {
        const additionalBalance = getBalance(poolComposition, additionalAsset);
        if (additionalBalance > 0 && additionalAsset !== baseCurrency) {
          await trade({ protocol: 'dhedge', from: additionalAsset, to: baseCurrency, platform: 'toros', network, share, slippage, pool, maxUsd, manager, apiKey });
          await sleep(500);
          const newComp = await poolComp(pool, network, protocol);
          if (newComp) poolComposition = newComp;
        }
      }

      await trade({ protocol: 'dhedge', from: 'USDC', to: tradeCurrency, platform: 'toros', network, share, slippage, pool, maxUsd, manager, apiKey });
      await sleep(500);
      const newComp = await poolComp(pool, network, protocol);
      if (newComp) poolComposition = newComp;
    } else {
      console.log(`Error: shorts not enabled on this network: ${network} / pool: ${pool} / apiKey: ${apiKey}`);
      return;
    }
  }

  // --- Allocation threshold gating (tradebot.R lines 158-197) ---
  usdValue = getBalance(poolComposition, 'USDC');
  usdcValue = usdValue;
  tradeBalance = getBalance(poolComposition, tradeCurrency);
  const assetUsdValue = price * tradeBalance;
  const totalUsd = usdValue + assetUsdValue;
  console.log(`Total Pool USD Value: ${totalUsd}`);
  const allocation = totalUsd === 0 ? 0 : assetUsdValue / totalUsd;

  console.log(`pair: ${pair} / side: ${side} / from: ${from} / to: ${to}`);
  console.log(`coin allocation: ${allocation} / coin usd value: ${assetUsdValue} / total usdc value: ${usdValue}`);

  if (!Number.isNaN(allocation)) {
    const condition1 = allocation < (1 - threshold / 100) && side === 'buy';
    // NOTE: R's tradebot.R lines 183-184 compute condition2 from the
    // allocation/threshold check, then immediately hardcode
    // `condition2 = TRUE` on the very next line, permanently overriding it.
    // This means in R, ANY "sell" (or any side reaching this point when
    // condition1 is false) always executes the trade unconditionally
    // regardless of allocation. This looks like leftover debug code, but
    // since it is live production behavior we replicate it exactly rather
    // than "fixing" it — changing this would materially change when trades
    // fire.
    const condition2 = true;
    if (condition1 || condition2) {
      console.log('trading conditions satisfied, entering trading code inside the tradebot function');
      const res = await trade({ protocol: 'dhedge', from, to, share, slippage, network, pool, platform, maxUsd, manager, apiKey });
      console.log('response from trade function:', res);
    } else {
      console.log('All dhedgev2 sides are ok');
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// executeTrades() (src/api/executeTrades.R, full file)
// Per-side (long/neutral/short/hold) orchestration, including short-network
// bear/bull token substitution.
// ---------------------------------------------------------------------------
export type ExecuteTradesParams = {
  pool: string;
  pair: string;
  share: number;
  network: string;
  threshold: number;
  slippage: number;
  platform: string;
  protocol: string;
  maxUsd: number | null;
  composition: Composition | null;
  side: 'long' | 'neutral' | 'short' | 'hold';
  apiKey: string;
};

export async function executeTrades(params: ExecuteTradesParams): Promise<{ status: string; status_code: number | string; message: string }> {
  try {
    console.log(`executeTrades invoked using this api key: ${params.apiKey}`);
    let composition = params.composition;
    if (!composition) {
      composition = await poolComp(params.pool, params.network, params.protocol);
    }

    const splitPair = params.pair.split('-');
    const tradePair = splitPair[0];
    const basePair = splitPair[1];
    const pair = `${tradePair}-${basePair}`;
    const price = getUsdPrice(tradePair, composition);
    console.log(`network: ${params.network} / pair: ${pair} / pool: ${params.pool} / price: ${price.toFixed(4)} / side: ${params.side}`);

    const common = {
      pool: params.pool,
      share: params.share,
      slippage: params.slippage,
      threshold: params.threshold,
      price,
      network: params.network,
      platform: params.platform,
      protocol: params.protocol,
      maxUsd: params.maxUsd,
      apiKey: params.apiKey,
      poolComposition: composition,
    };

    if (params.side === 'long') {
      await tradebot({ ...common, pair, side: 'buy' });
    } else if (params.side === 'neutral') {
      console.log('sending sell to dhedgev2');
      await tradebot({ ...common, pair, side: 'sell' });
      let again = false;
      let bearPair = pair;
      if (SHORT_NETWORKS.includes(params.network)) {
        if (isBtc(tradePair)) { bearPair = 'BTCBEAR1X-USDC'; again = true; }
        else if (isEth(tradePair)) { bearPair = 'ETHBEAR1X-USDC'; again = true; }
      }
      if (again) {
        await tradebot({ ...common, pair: bearPair, platform: 'toros', side: 'sell' });
      }
    } else if (params.side === 'short') {
      console.log('selling the trade asset invoking tradebot');
      await tradebot({ ...common, pair, side: 'sell' });
      let again = false;
      let bearPair = pair;
      if (SHORT_NETWORKS.includes(params.network)) {
        if (isBtc(tradePair)) { bearPair = 'BTCBEAR1X-USDC'; again = true; }
        else if (isEth(tradePair)) { bearPair = 'ETHBEAR1X-USDC'; again = true; }
      }
      if (again) {
        console.log('buying the short side of the trade');
        await tradebot({ ...common, pair: bearPair, platform: 'toros', side: 'buy' });
      }
      return { status: 'success', status_code: 200, message: 'executeTrades succesfully invoked' };
    } else if (params.side === 'hold') {
      return { status: 'success', status_code: 200, message: 'executeTrades succesfully invoked' };
    }
    return { status: 'success', status_code: 200, message: 'executeTrades succesfully invoked' };
  } catch (e: any) {
    return { status: 'fail', status_code: 400, message: e.message };
  } finally {
    await sleep(1000);
  }
}
