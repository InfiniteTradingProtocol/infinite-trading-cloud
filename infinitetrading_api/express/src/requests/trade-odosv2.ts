import { Router, Request, Response } from "express";
import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { dhedgev2 } from "../dhedge";
import { getTxOptions } from "../utils/txOptions";
import { handleDexError } from "../utils/dex-ban";

const tradeOdosV2Router = Router();

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

// Track last ODOS request time per chain to enforce global rate limiting
const lastOdosRequest: Record<number, number> = {};
const ODOS_MIN_DELAY_MS = 5000; // 5 seconds between ODOS requests globally

// Helper: Use ODOS v3 via dhedge SDK
export async function tryOdosV2ThenV3({
  pool,
  assetFrom,
  assetTo,
  amountIn,
  slippage,
  txOptions,
  estimateGasOnly = false
}: {
  pool: any,
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
  
  // Enforce global rate limiting for ODOS
  const now = Date.now();
  const lastRequest = lastOdosRequest[chainId] || 0;
  const timeSinceLastRequest = now - lastRequest;
  
  if (timeSinceLastRequest < ODOS_MIN_DELAY_MS) {
    const waitTime = ODOS_MIN_DELAY_MS - timeSinceLastRequest;
    console.log(`[ODOS] ⏳ Rate limiting: waiting ${waitTime}ms before request`);
    await sleep(waitTime);
  }
  
  lastOdosRequest[chainId] = Date.now();
  
  // Use ODOS v3 via dhedge SDK
  let retryCount = 0;
  const maxRetries = 3;
  let result: any;
  
  while (retryCount <= maxRetries) {
    try {
      console.log(`[ODOS v3] Making request to quote endpoint`);
      if (estimateGasOnly) {
        result = await pool.trade(Dapp.ODOS, assetFrom, assetTo, amountIn, slippage, txOptions, { estimateGas: true });
        console.log(`✅ [ODOS v3] Gas estimation successful`);
      } else {
        result = await pool.trade(Dapp.ODOS, assetFrom, assetTo, amountIn, slippage, txOptions);
        console.log(`✅ [ODOS v3] Trade successful: ${result.hash}`);
      }
      return { ...result, used: "v3" };
    } catch (error: any) {
      const errorMsg = error?.response?.data?.detail || error?.message || String(error);
      if (errorMsg.includes('429') || errorMsg.includes('rate limit') || errorMsg.includes('Too Many Requests') || errorMsg.includes('Requests per')) {
        retryCount++;
        if (retryCount > maxRetries) {
          console.error(`[ODOS 429] Failed after ${maxRetries} retries. Please upgrade your ODOS API plan or reduce request frequency.`);
          throw error;
        }
        const backoffMs = retryCount * 1000;
        console.log(`[ODOS 429] Rate limited! Retry ${retryCount}/${maxRetries} after ${backoffMs}ms`);
        console.log(`[ODOS 429] Error: ${errorMsg}`);
        await sleep(backoffMs);
      } else {
        // Check if should be banned for other errors
        await handleDexError(network, "odos", error);
        throw error;
      }
    }
  }
  
  throw new Error('ODOS v3 trade failed after retries');
}

// POST /trade-odosv2 - For testing ODOS v3 directly
tradeOdosV2Router.post("/trade-odosv2", async (req: Request, res: Response) => {
  const { network, poolAddress, assetFrom, assetTo, amountIn, slippage, odosApiKey, provider, key } = req.body;
  if (!network || !poolAddress || !assetFrom || !assetTo || !amountIn || !slippage || !odosApiKey) {
    return res.status(400).json({ error: "Missing required parameters" });
  }
  try {
    const dhedge = await dhedgev2(network, odosApiKey, provider || null, key || null);
    const pool = await dhedge.loadPool(poolAddress);
    const txOptions = await getTxOptions(network, provider || null, key || null);
    
    const result = await tryOdosV2ThenV3({
      pool,
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

export default tradeOdosV2Router;
