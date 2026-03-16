import { Router, Request, Response } from "express";
import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import axios from "axios";
import { dhedgev2 } from "../dhedge";
import { getTxOptions } from "../utils/txOptions";
import { txFees, apiPaymentFixed } from "../txFees";


import * as dotenv from 'dotenv';
dotenv.config({ path: '../../.env' });
const DAO_GAS = process.env.DAO_GAS;

const tradeOdosV2Router = Router();

// Network chain ID mapping
const networkChainIdMap: Record<string, number> = {
  ETHEREUM: 1,
  POLYGON: 137,
  OPTIMISM: 10,
  ARBITRUM: 42161,
  BASE: 8453
};

// Helper: Try ODOS v2 first (with DAO referral), fallback to v3
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
  
  // Try ODOS v2 with DAO referral first
  try {
    console.log(`[ODOS] Trying v2 with DAO referral...`);
    
    // Build v2 quote params with referral
    const quoteParams: any = {
      chainId,
      inputTokens: [{ tokenAddress: assetFrom, amount: amountIn.toString() }],
      outputTokens: [{ tokenAddress: assetTo, proportion: 1 }],
      slippageLimitPercent: slippage,
      userAddr: pool.address,
      compact: false
    };
    
    // Add DAO referral if configured
    if (DAO_GAS && ethers.utils.isAddress(DAO_GAS)) {
      quoteParams.referralFee = 2; // 0.02%
      quoteParams.referralFeeRecipient = DAO_GAS;
      console.log(`[ODOS v2] Using DAO referral: ${DAO_GAS}`);
    }
    
    const odosApiKey = process.env.ODOS_API_KEY;
    if (!odosApiKey) {
      throw new Error('ODOS_API_KEY not configured');
    }
    
    const odosBaseUrl = "https://enterprise-api.odos.xyz/sor";
    const headers = {
      "Content-Type": "application/json",
      "x-api-key": odosApiKey
    };
    
    // Get quote
    const quoteResult = await axios.post(`${odosBaseUrl}/quote/v3`, quoteParams, { headers });
    
    // Get assembled transaction
    const assembleResult = await axios.post(
      `${odosBaseUrl}/assemble`,
      { pathId: quoteResult.data.pathId, userAddr: pool.address },
      { headers }
    );
    
    console.log(`✅ [ODOS v2] Quote successful, using referral to DAO`);
    
    // If only estimating gas, return early
    if (estimateGasOnly) {
      return { gas: "500000", used: "v2" }; // Conservative estimate
    }
    
    // Execute the transaction via pool (using the assembled tx data)
    // Note: This would need to be integrated into the pool's trade execution logic
    return { swapTxData: assembleResult.data.transaction.data, minAmountOut: assembleResult.data.outputTokens[0].amount, used: "v2" };
    
  } catch (v2Error: any) {
    console.warn(`[ODOS v2] Failed:`, v2Error?.response?.data || v2Error.message);
    console.log(`[ODOS] Falling back to v3 (via SDK)...`);
    
    // Fall back to ODOS v3 via dhedge SDK (no referral)
    try {
      if (estimateGasOnly) {
        const gasEst = await pool.trade(Dapp.ODOS, assetFrom, assetTo, amountIn, slippage, txOptions, { estimateGas: true });
        console.log(`✅ [ODOS v3] Gas estimation successful`);
        return { ...gasEst, used: "v3" };
      } else {
        const tx = await pool.trade(Dapp.ODOS, assetFrom, assetTo, amountIn, slippage, txOptions);
        console.log(`✅ [ODOS v3] Trade successful: ${tx.hash}`);
        return { ...tx, used: "v3" };
      }
    } catch (v3Error: any) {
      console.error(`❌ [ODOS] Both v2 and v3 failed`);
      throw new Error(`ODOS trade failed: v2 (${v2Error.message}), v3 (${v3Error.message})`);
    }
  }
}

// POST /trade-odosv2 - For testing the v2 fallback directly
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
