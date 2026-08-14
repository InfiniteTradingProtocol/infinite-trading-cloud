import { Router, Request, Response } from "express";
import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { dhedgev2 } from "../dhedge";
import { getTxOptions } from "../utils/txOptions";
import { handleDexError } from "../utils/dex-ban";
import { parseDapp } from "../utils/parseDapp";

const tradeDexRouter = Router();

// Network chain ID mapping
const networkChainIdMap: Record<string, number> = {
  ETHEREUM: 1,
  POLYGON: 137,
  OPTIMISM: 10,
  ARBITRUM: 42161,
  BASE: 8453
};

// Sleep helper for rate limiting
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

// Track last request time per DEX per chain for rate limiting
const lastDexRequest: Record<string, Record<number, number>> = {};
const DEX_MIN_DELAY_MS = 500; // 500ms between requests per DEX

// Helper: Execute DEX trade with retry logic and rate limiting
export async function executeDexTrade({
  pool,
  dapp,
  assetFrom,
  assetTo,
  amountIn,
  slippage,
  txOptions,
  estimateGasOnly = false
}: {
  pool: any,
  dapp: Dapp,
  assetFrom: string,
  assetTo: string,
  amountIn: ethers.BigNumber | string,
  slippage: number,
  txOptions: any,
  estimateGasOnly?: boolean
}) {
  const network = pool.network;
  const networkKey = typeof network === 'string' ? network.toUpperCase() : network;
  const chainId = networkChainIdMap[networkKey] ?? 137;
  const dexName = dapp.toLowerCase();

  // Enforce rate limiting per DEX
  if (!lastDexRequest[dexName]) {
    lastDexRequest[dexName] = {};
  }

  const now = Date.now();
  const lastRequest = lastDexRequest[dexName][chainId] || 0;
  const timeSinceLastRequest = now - lastRequest;

  if (timeSinceLastRequest < DEX_MIN_DELAY_MS) {
    const waitTime = DEX_MIN_DELAY_MS - timeSinceLastRequest;
    console.log(`[${dapp}] ⏳ Rate limiting: waiting ${waitTime}ms before request`);
    await sleep(waitTime);
  }

  lastDexRequest[dexName][chainId] = Date.now();

  // Execute trade with retry logic
  let retryCount = 0;
  const maxRetries = 3;
  let result: any;

  while (retryCount <= maxRetries) {
    try {
      console.log(`[${dapp}] Making request to quote endpoint`);
      if (estimateGasOnly) {
        result = await pool.trade(dapp, assetFrom, assetTo, amountIn, slippage, txOptions, { estimateGas: true });
        console.log(`✅ [${dapp}] Gas estimation successful`);
      } else {
        result = await pool.trade(dapp, assetFrom, assetTo, amountIn, slippage, txOptions);
        console.log(`✅ [${dapp}] Trade successful: ${result.hash}`);
      }
      return result;
    } catch (error: any) {
      const errorMsg = error?.response?.data?.detail || error?.message || String(error);
      if (errorMsg.includes('429') || errorMsg.includes('rate limit') || errorMsg.includes('Too Many Requests') || errorMsg.includes('Requests per')) {
        retryCount++;
        if (retryCount > maxRetries) {
          console.error(`[${dapp} 429] Failed after ${maxRetries} retries. Rate limit exceeded.`);
          throw error;
        }
        const backoffMs = retryCount * 1000;
        console.log(`[${dapp} 429] Rate limited! Retry ${retryCount}/${maxRetries} after ${backoffMs}ms`);
        console.log(`[${dapp} 429] Error: ${errorMsg}`);
        await sleep(backoffMs);
      } else {
        // Check if should be banned for other errors
        await handleDexError(network, dexName as any, error);
        throw error;
      }
    }
  }

  throw new Error(`${dapp} trade failed after retries`);
}

// POST /trade-dex - Test DEX trade with rate limiting and retry logic
tradeDexRouter.post("/trade-dex", async (req: Request, res: Response) => {
  const { network, poolAddress, assetFrom, assetTo, amountIn, slippage, dapp, apiKey, provider, key } = req.body;
  if (!network || !poolAddress || !assetFrom || !assetTo || !amountIn || !slippage || !dapp || !apiKey) {
    return res.status(400).json({ error: "Missing required parameters" });
  }
  try {
    const dhedge = await dhedgev2(network, apiKey, provider || null, key || null);
    const pool = await dhedge.loadPool(poolAddress);
    const txOptions = await getTxOptions(network, provider || null, key || null);
    const resolvedDapp = parseDapp(dapp as string);

    const result = await executeDexTrade({
      pool,
      dapp: resolvedDapp,
      assetFrom,
      assetTo,
      amountIn,
      slippage,
      txOptions,
      estimateGasOnly: false
    });

    return res.json({ status: "success", result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message || String(err) || "Unknown error" });
  }
});

export default tradeDexRouter;
