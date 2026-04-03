import { Dapp, ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { BigNumber } from "ethers"
const tradeRouter = Router();
import { Request, Response } from "express";
import { getBalanceFromComposition } from "../utils/pool";
import { getTxOptions } from "../utils/txOptions";
import { dhedge,dhedgev2 } from "../dhedge";
import { wallet } from "../wallet";
import { walletv2 } from "../walletv2";
import { apiPayment, apiPaymentFixed, feeData, txFees } from "../txFees";
import { rpc, getAllRpcProviders } from "../rpc";
import { RetryProvider, createRetryProviderWithFailover } from "../utils/RetryProvider";
import { getRedis } from "../lib/redis";
import axios from "axios";
import { tryOdosV2ThenV3 } from "./trade-dex";
import { tradeWithFallback, executeTradeWithFallback } from "./trade-fallback";
import { approveIfNeeded } from "../utils/dex-approve";
import { getBannedDexs, unbanDex } from "../utils/dex-ban";

// Error response helper
function sendErrorResponse(res: Response, statusCode: number, errorCode: number, message: string, errorType: string, details?: any) {
  const response: any = {
    status: "fail",
    status_code: errorCode,
    message: message,
    error_type: errorType
  };
  if (details) {
    response.details = details;
  }
  res.status(statusCode).send(response);
}




// helper: wait with a timeout + status check
async function waitForSuccess(tx: ethers.providers.TransactionResponse, timeoutMs = 30_000, confirmations = 1) {
  const timer = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("Transaction receipt timeout")), timeoutMs)
  );
  const receipt = await Promise.race([
    tx.wait(confirmations),
    timer,
  ]);
  if (!receipt || receipt.status !== 1) {
    throw new Error(`Transaction failed or reverted (hash: ${tx.hash})`);
  }
  return receipt;
}

//jest.setTimeout(100000);

//(async () => {
//    const assetAddress = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6';
//    const contractAddress = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6';
//    const amount = ethers.utils.parseEther("100");
//    console.log(amount)
//    // The network variable was removed since it's not used in this scope.
//    const erc20ABI = '[{"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}]'; // Simplified ABI for demonstration
//    const manager = 'infinitetrading'; // Ensure you have this function correctly defined to return a signer
//    let network = Network.POLYGON;
//    const signer = wallet(network,manager); // Assuming wallet returns a correctly initialized ethers.Signer
//    await checkallowance(assetAddress, contractAddress, amount, erc20ABI, signer);
//    estimateGasForMethod();
//})();

const erc20ABI = JSON.stringify([
    // Minimal ERC20 ABI for allowance and approve
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)"
]);

const MAX_ALLOWANCE = ethers.constants.MaxUint256

/**
 * Ban a wallet address for 15 minutes due to insufficient gas
 */
export async function banWalletForInsufficientGas(walletAddress: string): Promise<void> {
    try {
        const redis = await getRedis();
        const banKey = `wallet_ban:insufficient_gas:${walletAddress.toLowerCase()}`;
        // Set ban for 15 minutes (900 seconds)
        await redis.setEx(banKey, 900, Date.now().toString());
        console.log(`⛔ Wallet ${walletAddress} banned for 15 minutes due to insufficient gas`);
    } catch (error) {
        console.error("Failed to ban wallet in Redis:", error);
    }
}

/**
 * Check if a wallet is currently banned
 */
async function isWalletBanned(walletAddress: string): Promise<boolean> {
    try {
        const redis = await getRedis();
        const banKey = `wallet_ban:insufficient_gas:${walletAddress.toLowerCase()}`;
        const banned = await redis.get(banKey);
        return banned !== null;
    } catch (error) {
        console.error("Failed to check wallet ban in Redis:", error);
        return false; // If Redis fails, don't block the transaction
    }
}

/**
 * Track internal revert failures for a wallet
 * If a wallet has 3+ internal reverts in 5 minutes, ban it for 15 minutes
 */
export async function trackInternalRevert(walletAddress: string, txHash: string, reason: string): Promise<void> {
    try {
        const redis = await getRedis();
        const trackingKey = `wallet_internal_reverts:${walletAddress.toLowerCase()}`;
        const now = Date.now();
        
        // Get existing failures
        const existingData = await redis.get(trackingKey);
        const failures: Array<{timestamp: number, txHash: string, reason: string}> = existingData ? JSON.parse(existingData) : [];
        
        // Add new failure
        failures.push({ timestamp: now, txHash, reason });
        
        // Remove failures older than 5 minutes (300000ms)
        const recentFailures = failures.filter(f => now - f.timestamp < 300000);
        
        console.warn(`⚠️  Internal revert tracked for wallet ${walletAddress} (${recentFailures.length} in last 5 min)`);
        console.warn(`   TX: ${txHash}, Reason: ${reason}`);
        
        // If 3+ failures in 5 minutes, ban the wallet
        if (recentFailures.length >= 3) {
            console.error(`❌ BANNING WALLET: ${walletAddress} - ${recentFailures.length} internal reverts in 5 minutes`);
            await banWalletForInsufficientGas(walletAddress);
            
            // Clear tracking since wallet is now banned
            await redis.del(trackingKey);
        } else {
            // Save updated failures list (expires in 5 minutes)
            await redis.setEx(trackingKey, 300, JSON.stringify(recentFailures));
        }
    } catch (error) {
        console.error("Failed to track internal revert in Redis:", error);
    }
}

/**
 * Check if wallet has sufficient gas balance for a transaction
 * REUSABLE: Returns balance to avoid redundant RPC calls
 */
export async function checkGasBalance(
    network: Network,
    walletAddress: string,
    gasLimit: string | ethers.BigNumber,
    maxFeePerGas: string | ethers.BigNumber,
    providerName: string,
    existingBalance?: ethers.BigNumber
): Promise<{ sufficient: boolean; balance: ethers.BigNumber; required: ethers.BigNumber }> {
    // Calculate total gas cost
    const gasLimitBN = ethers.BigNumber.from(gasLimit);
    const maxFeePerGasBN = ethers.BigNumber.from(maxFeePerGas);
    const totalGasCost = gasLimitBN.mul(maxFeePerGasBN);
    
    // Use existing balance if provided, otherwise fetch it
    let gasBalance: ethers.BigNumber;
    if (existingBalance) {
        gasBalance = existingBalance;
    } else {
        const providerUrls = getAllRpcProviders(network);
        const rpc_provider = createRetryProviderWithFailover(providerUrls);
        gasBalance = await rpc_provider.getBalance(walletAddress);
    }
    
    const sufficient = gasBalance.gte(totalGasCost);
    
    if (!sufficient) {
        const gasToken = network === Network.POLYGON ? 'MATIC' : 'ETH';
        const gasBalanceFormatted = ethers.utils.formatEther(gasBalance);
        const gasCostFormatted = ethers.utils.formatEther(totalGasCost);
        const shortfall = ethers.utils.formatEther(totalGasCost.sub(gasBalance));
        
        console.error(
            `❌ Insufficient gas via ${providerName}:\n` +
            `   Wallet: ${walletAddress}\n` +
            `   Balance: ${gasBalanceFormatted} ${gasToken}\n` +
            `   Required: ${gasCostFormatted} ${gasToken}\n` +
            `   Shortfall: ${shortfall} ${gasToken}\n` +
            `   🚫 PREVENTING FAILED TRANSACTION - Would waste customer gas!`
        );
    }
    
    return { sufficient, balance: gasBalance, required: totalGasCost };
}

/**
 * Auto-approve token for trading when allowance is insufficient
 * CRITICAL: Checks gas balance BEFORE sending transaction to prevent wasting customer gas
 * OPTIMIZED: Accepts optional gas balance to avoid redundant RPC calls
 */
async function autoApproveToken(
    network: Network,
    poolAddress: string,
    assetAddress: string,
    platform: string,
    apiKey: string,
    provider: string | null,
    key: string | null,
    existingGasBalance?: ethers.BigNumber
): Promise<boolean> {
    const providers = ['alchemy', 'infura', 'drpc'];
    let lastError: any = null;
    let currentGasBalance = existingGasBalance;
    
    for (const providerName of providers) {
        try {
            console.log(`🔓 Auto-approving ${assetAddress} for ${platform} on pool ${poolAddress} via ${providerName}...`);
            
            const dHedge = await dhedgev2(network, apiKey, providerName, key);
            const pool = await dHedge.loadPool(poolAddress);
            
            // Map platform to Dapp
            let dApp: Dapp;
            const platformLower = platform.toLowerCase();
            if (platformLower === "uniswapv3") dApp = "uniswapV3" as Dapp;
            else if (platformLower === "oneinch" || platformLower === "1inch") dApp = Dapp.ONEINCH;
            else if (platformLower === "aave" || platformLower === "aavev3") dApp = Dapp.AAVEV3;
            else if (platformLower === "toros") dApp = Dapp.TOROS;
            else if (platformLower === "odos") dApp = "odos" as Dapp;
            else dApp = platform as Dapp;
            
            const txOptions = await getTxOptions(pool.network, providerName, key);
            const estimatedGas = await pool.approve(dApp, assetAddress, ethers.constants.MaxUint256, txOptions, true);
            const txOptions2 = await txFees(network, providerName, key, estimatedGas);
            
            // Get wallet address for balance check
            const wallet = await walletv2(network, apiKey, providerName, key);
            
            // CRITICAL FIX: Check gas balance BEFORE sending approval transaction
            // OPTIMIZED: Reuse existing balance if provided to save RPC calls
            const gasCheck = await checkGasBalance(
                network,
                wallet.address,
                txOptions2.gasLimit,
                txOptions2.maxFeePerGas,
                providerName,
                currentGasBalance
            );
            
            // Update current balance for potential retry on next provider
            currentGasBalance = gasCheck.balance;
            
            if (!gasCheck.sufficient) {
                // Try next provider instead of wasting gas on a guaranteed failure
                if (providerName !== providers[providers.length - 1]) {
                    console.log(`🔄 Trying next provider...`);
                    continue;
                } else {
                    // All providers failed - ban wallet to avoid wasting resources
                    await banWalletForInsufficientGas(wallet.address);
                    const gasToken = network === Network.POLYGON ? 'MATIC' : 'ETH';
                    throw new Error(`Insufficient ${gasToken} for approval gas. Wallet banned for 15 minutes. Balance: ${ethers.utils.formatEther(gasCheck.balance)}, Required: ${ethers.utils.formatEther(gasCheck.required)}`);
                }
            }
            
            console.log(`✅ Sufficient gas balance - proceeding with approval...`);
            const tx = await pool.approve(dApp, assetAddress, ethers.constants.MaxUint256, txOptions2);
            
            console.log(`✅ Auto-approve tx submitted via ${providerName}: ${tx.hash}`);
            const receipt = await tx.wait();
            console.log(`✅ Auto-approve confirmed: ${receipt.transactionHash}`);
            
            // Send API payment for the approve transaction
            await apiPaymentFixed(network, apiKey, tx, 'approve', providerName, key, null);
            
            return true;
        } catch (error) {
            lastError = error;
            const errorMsg = error instanceof Error ? error.message : String(error);
            console.error(`❌ Auto-approve failed via ${providerName}: ${errorMsg.substring(0, 150)}`);
            
            // If not the last provider, try next one
            if (providerName !== providers[providers.length - 1]) {
                console.log(`🔄 Trying next provider...`);
                continue;
            }
        }
    }
    
    // All providers failed
    console.error(`❌ Auto-approve failed on all providers:`, lastError);
    return false;
}

async function checkAllowance(network: Network, assetAddress: string, contractAddress: string, poolAddress: string,provider: string | null,key: string | null) {
   try {
    const providerUrls = getAllRpcProviders(network);
    const rpc_provider = createRetryProviderWithFailover(providerUrls);
    const tokenContract = new ethers.Contract(assetAddress, erc20ABI, rpc_provider);
    const allowed = await tokenContract.allowance(poolAddress, contractAddress);
    return allowed.eq(MAX_ALLOWANCE)
   }
   catch(error) { throw error }
}

tradeRouter.get("/checkAllowance", async (req: Request, res: Response) => {
  try {
    let network: Network = Network.POLYGON; 
    if (req.query.network) network = req.query.network as Network;
    const assetAddress = req.body.asset;
    const contractAddress = req.body.contract;
    const poolAddress = req.body.pool;
    let manager = null; let apiKey = null; let provider = null; let key = null;
    if (req.query.provider) provider = req.query.provider as string; 
    if (req.query.key) key = req.query.key as string; 
    else manager = "infinitetrading" 
    if (req.query.manager) manager = req.query.manager as string;
    if (!ethers.utils.isAddress(assetAddress)) throw new Error(`Invalid asset address: ${assetAddress}`);
    if (!ethers.utils.isAddress(contractAddress)) throw new Error(`Invalid contract address: ${contractAddress}`);
    if (!ethers.utils.isAddress(poolAddress)) throw new Error(`Invalid pool address: ${poolAddress}`);
    const isAllowed = await checkAllowance(network,assetAddress,contractAddress,poolAddress,provider,key);
    res.status(200).send({ status: "success", msg: isAllowed });
  } catch (error) {
    const message = (error instanceof Error) ? error.message : JSON.stringify(error);
    console.error(`❌ checkAllowance failed: ${message.substring(0, 150)}`);
    sendErrorResponse(res, 400, 2011, message, "check_allowance_failed");
  }
});

tradeRouter.post("/approve", async (req: Request, res: Response) => {
  try {
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    const poolAddress = req.query.pool as string;
    let manager = null; let provider = 'alchemy'; let key = null; 
    if (req.query.provider) provider = req.query.provider as string;
    if (req.query.key) key = req.query.key as string;
    let apiKey; let pool;
    if (req.query.manager) manager = req.query.manager as string;
    if (req.query.apiKey) {
	    apiKey = req.query.apiKey as string;
	    let dHedge = await dhedgev2(network,apiKey,provider,key)
	    //console.log(dHedge)
	    pool = await dHedge.loadPool(poolAddress);
    }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    const txOptions = await getTxOptions(pool.network,provider,key);
    let dApp;
    if (req.query.platform) {
        const platform = (req.query.platform as string).toLowerCase();
        if (platform == "uniswapv3") dApp = "uniswapV3" as Dapp
	else if (platform == "oneinch") dApp = Dapp.ONEINCH;
        else if (platform == "1inch") dApp = Dapp.ONEINCH;
	else if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
        else dApp = req.query.platform as Dapp;
    }
    else throw "platform parameter missing"
    
    // Use smart approval: checks allowance first, only approves if needed
    const approved = await approveIfNeeded(
        network,
        poolAddress,
        req.body.asset,
        ethers.constants.MaxUint256,
        dApp,
        pool
    );
    
    if (!approved) {
        throw new Error("Approval failed");
    }
    
    // Always return success response whether we approved or allowance was already sufficient
    console.log(`✅ Token approval ensured for ${dApp}`);
    res.status(200).send({ 
        status: "success", 
        msg: "Token approval confirmed",
        alreadyApproved: false // For backwards compatibility, we say we approved
    });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : JSON.stringify(err);
    console.error(`❌ Approve failed: ${message.substring(0, 150)}`);
    sendErrorResponse(res, 400, 2010, message, "approve_failed");
  }
});
tradeRouter.get("/trade", async (req: Request, res: Response) => {
  // Declare variables outside try block so they're accessible in catch for retry logic
  let network: Network | undefined;
  let pool: any;
  let assetA: string | undefined;
  let assetB: string | undefined;
  let tradeAmount: ethers.BigNumber | undefined;
  let slippage: string | number | undefined;
  let poolAddress: string | undefined;
  let dApp: any;
  let txOptions: any;
  let apiKey: string | null = null;
  let provider: string = 'infura';
  let key: string | null = null;
  
  try {
    console.log("trade endpoint invoked")
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    let withdrawal = false;
    if (req.query.withdrawal !== undefined) {
    	withdrawal = req.query.withdrawal === "true" || req.query.withdrawal === "1";
    }
    assetA = req.query.from as string;
    assetB = req.query.to as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    // Parse slippage and ensure it's a clean number with max 2 decimal places
    const slippageRaw = req.query.slippage as string;
    const slippageParsed = parseFloat(slippageRaw);
    slippage = isNaN(slippageParsed) ? "0.5" : Math.round(slippageParsed * 100) / 100;
    poolAddress = req.query.pool as string;
    let feeAmount = 500;
    if (req.query.feeAmount) { feeAmount = req.query.feeAmount as unknown as number; }
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    
    // Get wallet address for ban checking and logging
    const walletAddress = pool.address; // This is the pool's wallet address
    
    // Check if wallet is banned due to insufficient gas
    const isBanned = await isWalletBanned(walletAddress);
    if (isBanned) {
        console.log(`⛔ Trade rejected: Wallet ${walletAddress} is banned for insufficient gas. Please refill gas and wait.`);
        res.status(429).send({
            status: "fail",
            msg: `Wallet ${walletAddress} is temporarily banned due to insufficient gas. Please refill gas and try again in a few minutes.`,
            error_type: "wallet_banned",
            wallet_address: walletAddress
        });
        return;
    }
    
    let tradeAmount: ethers.BigNumber;
    const composition = await pool.getComposition();
    const balance = getBalanceFromComposition(assetA,composition);
    
    // Validate we have balance to trade
    if (balance.isZero()) {
        const errorMsg = `No balance available for ${assetA} in vault ${poolAddress}`;
        console.error(`❌ ${errorMsg}`);
        res.status(400).send({
            status: "fail",
            msg: errorMsg,
            error_type: "insufficient_balance",
            asset: assetA,
            balance: "0"
        });
        return;
    }
    
    if (req.query.share) {
            const share = req.query.share as string;
            const shareNum = parseFloat(share);
            
            // Validate share is reasonable
            if (shareNum <= 0 || shareNum > 100) {
                const errorMsg = `Invalid share value: ${share}. Must be between 0 and 100.`;
                console.error(`❌ ${errorMsg}`);
                res.status(400).send({
                    status: "fail",
                    msg: errorMsg,
                    error_type: "invalid_share"
                });
                return;
            }
            
            // If share is exactly 100, use full balance without safety margin
            if (shareNum === 100) {
                tradeAmount = balance;
                console.log(`[Trade] Using 100% of balance (no safety margin): ${ethers.utils.formatUnits(balance, 18)}`);
            } else {
                tradeAmount = balance.mul(share).div(100);
                // Apply 99.9% safety margin to prevent BigNumber precision issues causing amount > balance
                tradeAmount = tradeAmount.mul(999).div(1000);
                
                // Final safety check - never exceed balance
                if (tradeAmount.gt(balance)) {
                    tradeAmount = balance;
                }
            }
    }
    else if (req.query.amount) {
        const amount = req.query.amount as string;
        tradeAmount = ethers.BigNumber.from(amount);
        
        // If requested amount exceeds balance, cap to balance (with safety margin)
        if (tradeAmount.gt(balance)) {
            console.warn(`⚠️ Requested amount ${ethers.utils.formatUnits(tradeAmount, 18)} exceeds balance ${ethers.utils.formatUnits(balance, 18)}. Capping to balance.`);
            // Use 99.9% of balance to prevent precision issues
            tradeAmount = balance.mul(999).div(1000);
            if (tradeAmount.gt(balance)) {
                tradeAmount = balance;
            }
        }
    }
    else throw "share or amount parameters missing";
    
    // Final validation: ensure we're not trying to trade 0
    if (tradeAmount.isZero()) {
        const errorMsg = `Trade amount is zero after calculation. Balance: ${ethers.utils.formatUnits(balance, 18)}`;
        console.error(`❌ ${errorMsg}`);
        res.status(400).send({
            status: "fail",
            msg: errorMsg,
            error_type: "zero_trade_amount"
        });
        return;
    }

    // Get wallet address for logging and ban checking
    const executingWallet = await pool.signer.getAddress();
    
    // 🔥 PROACTIVE GAS CHECK: Verify executing wallet has gas BEFORE estimating
    const providerUrls = getAllRpcProviders(network);
    const rpc_provider = createRetryProviderWithFailover(providerUrls);
    const gasBalance = await rpc_provider.getBalance(executingWallet);
    
    if (gasBalance.isZero()) {
        const errorMsg = `No gas in executing wallet ${executingWallet}. Please refill gas wallet.`;
        console.error(`❌ ${errorMsg}`);
        await banWalletForInsufficientGas(executingWallet);
        res.status(402).send({
            status: "fail",
            msg: errorMsg,
            error_type: "insufficient_gas",
            executing_wallet: executingWallet,
            current_balance: "0"
        });
        return;
    }

    // Format amounts for readable logging
    let formattedAmount = tradeAmount.toString();
    try {
        // Try to get decimals and format properly
        const providerUrls = getAllRpcProviders(network);
        const rpc_provider = createRetryProviderWithFailover(providerUrls);
        const tokenContract = new ethers.Contract(assetA, erc20ABI, rpc_provider);
        const decimals = await tokenContract.decimals();
        formattedAmount = ethers.utils.formatUnits(tradeAmount, decimals);
    } catch (e) {
        // If we can't get decimals, just use raw amount
        formattedAmount = tradeAmount.toString();
    }

    console.log(
      `📌 /trade | 🌐 ${network} | 📊 ${req.query.platform ?? "N/A"} | 💱 ${assetA} → ${assetB} | 💰 ${formattedAmount} (${tradeAmount.toString()} wei) | 🏊 ${poolAddress} | 👛 ${executingWallet} | 📉 ${slippage}% | 🔄 ${withdrawal} | 🌐 ${provider} | 🗝️ ${apiKey ? apiKey.substring(0, 16) + "..." : "None"} | 👤 ${manager ?? "Default"}`
    );
    txOptions = await getTxOptions(pool.network,provider,key);
    let tx;
    let txOptions2;
    const { BigNumber } = require("ethers");
    if (req.query.platform) {
        const platform = (req.query.platform as string).toLowerCase();
        if (platform == "uniswapv3") dApp = "uniswapV3" as Dapp;
        else if (platform == "oneinch") dApp = Dapp.ONEINCH;
        else if (platform == "1inch") dApp = Dapp.ONEINCH;
        else dApp = platform as Dapp;
    }
    else throw "platform parameter missing";
    let txHashes = [];
    let paymentTx = null;
    let gasBumpCount = 0;
    if (dApp == Dapp.UNISWAPV3) {
        let estimatedGas;
        estimatedGas = await pool.tradeUniswapV3(assetA,assetB,tradeAmount,feeAmount,+slippage,txOptions,true);
        console.log("estimated gas for uniswapV3:", estimatedGas?.toString?.() ?? 'null');
        
        // Check if wallet has enough gas for this specific transaction
        let txOptions2 = await txFees(network,provider,key,estimatedGas);
        const estimatedGasCost = ethers.BigNumber.from(txOptions2.gasLimit)
            .mul(ethers.BigNumber.from(txOptions2.maxFeePerGas));
        
        if (gasBalance.lt(estimatedGasCost)) {
            const errorMsg = `Insufficient gas for transaction. Need ${ethers.utils.formatEther(estimatedGasCost)} ETH, have ${ethers.utils.formatEther(gasBalance)} ETH. Wallet: ${executingWallet}`;
            console.error(`❌ ${errorMsg}`);
            await banWalletForInsufficientGas(executingWallet);
            res.status(402).send({
                status: "fail",
                msg: errorMsg,
                error_type: "insufficient_gas",
                executing_wallet: executingWallet,
                current_balance: ethers.utils.formatEther(gasBalance),
                required: ethers.utils.formatEther(estimatedGasCost)
            });
            return;
        }
        
        while (true) {
            try {
                tx = await pool.tradeUniswapV3(assetA,assetB,tradeAmount,feeAmount,+slippage,txOptions2);
                break;
            } catch (err) {
                const msg = (err instanceof Error) ? err.message : String(err);
                if (msg.includes('replacement transaction underpriced') && gasBumpCount < 3) {
                    console.warn('Replacement transaction underpriced, bumping gas price and retrying...');
                    txOptions2 = {
                        ...txOptions2,
                        maxFeePerGas: txOptions2.maxFeePerGas ? BigNumber.from(txOptions2.maxFeePerGas).mul(110).div(100).toString() : undefined,
                        maxPriorityFeePerGas: txOptions2.maxPriorityFeePerGas ? BigNumber.from(txOptions2.maxPriorityFeePerGas).mul(110).div(100).toString() : undefined
                    };
                    gasBumpCount++;
                    continue;
                }
                throw err;
            }
        }
        console.log("uniswapV3 trade tx hash:", tx.hash);
        txHashes.push(tx.hash);
        paymentTx = tx;
    }
    else {
        let estimatedGas = null;
        if (dApp === Dapp.TOROS) {
    		// --- First transaction ---
    		const estGas1 = await pool.trade(Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions, true);
    		console.log("Estimated gas for Toros trade:", estGas1);

    		// Handle both BigNumber/string and error object responses from SDK
    		const gasValue1 = (typeof estGas1 === 'object' && estGas1?.gas !== undefined) ? estGas1.gas : estGas1;
    		const txOptions1 = await txFees(network, provider, key, gasValue1?.toString?.() ?? null);
    		
    		// Check if wallet has enough gas for this specific transaction
    		const estimatedGasCost1 = ethers.BigNumber.from(txOptions1.gasLimit)
    		    .mul(ethers.BigNumber.from(txOptions1.maxFeePerGas));
    		
    		if (gasBalance.lt(estimatedGasCost1)) {
    		    const errorMsg = `Insufficient gas for Toros trade. Need ${ethers.utils.formatEther(estimatedGasCost1)} ETH, have ${ethers.utils.formatEther(gasBalance)} ETH. Wallet: ${executingWallet}`;
    		    console.error(`❌ ${errorMsg}`);
    		    await banWalletForInsufficientGas(executingWallet);
    		    res.status(402).send({
    		        status: "fail",
    		        msg: errorMsg,
    		        error_type: "insufficient_gas",
    		        executing_wallet: executingWallet,
    		        current_balance: ethers.utils.formatEther(gasBalance),
    		        required: ethers.utils.formatEther(estimatedGasCost1)
    		    });
    		    return;
    		}
    		
    		const tx1 = await pool.trade(Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions1);
		console.log("Toros trade tx hash:", tx1.hash);

    		txHashes.push(tx1.hash);
    		paymentTx = tx1; // ✅ only tx1 is used for API payment
		const r1 = await waitForSuccess(tx1, 45_000, 1);
		console.log(`✅ Toros trade confirmed | Block: ${r1.blockNumber} | Gas: ${r1.gasUsed.toString()} | Status: ${r1.status}`);

    		// --- Conditional second transaction ---
    		if (withdrawal) {
        		const estGas2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions, true);
        		console.log("Estimated gas for Toros Withdrawal:", estGas2);
        		// Handle both BigNumber/string and error object responses from SDK
        		const gasValue2 = (typeof estGas2 === 'object' && estGas2?.gas !== undefined) ? estGas2.gas : estGas2;
        		const txOptions2 = await txFees(network, provider, key, gasValue2?.toString?.() ?? null);
        		const tx2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions2, false);
			
        		console.log("Toros withdrawal tx hash:", tx2.hash);
        		const r2 = await tx2.wait();
        		console.log(`✅ Toros withdrawal confirmed | Block: ${r2.blockNumber} | Gas: ${r2.gasUsed.toString()} | Status: ${r2.status}`);
        		txHashes.push(tx2.hash);
        		tx = tx2; // If withdrawal happens, tx2 is the final transaction
    		} else { tx = tx1; }    
    	}
            else {
                if (req.query.platform != "toros" && req.query.platform != "oneinch" && req.query.platform != "1inch") {
                    // Use automatic DEX fallback for gas estimation
                    try {
                        console.log(`[Trade] Estimating gas with DEX fallback (primary: ${dApp})`);
                        estimatedGas = await tradeWithFallback({
                            pool,
                            network,
                            primaryDapp: dApp,
                            assetFrom: assetA,
                            assetTo: assetB,
                            amountIn: tradeAmount,
                            slippage: +slippage,
                            txOptions,
                            estimateGasOnly: true
                        });
                    } catch (fallbackError: any) {
                        const errorMsg = fallbackError?.message || fallbackError?.reason || String(fallbackError);
                        console.error("[Trade] All DEX fallbacks failed during gas estimation:", errorMsg);
                        throw fallbackError;
                    }
                    
                    // Check if gas estimation failed (for SDK errors returned as property)
                    if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
                        const gasError = (estimatedGas as any).gasEstimationError;
                        const errorMsg = gasError?.message || gasError?.reason || String(gasError);
                        console.error("Gas estimation failed:", errorMsg);
                        
                        // For generic "execution reverted" errors, try to diagnose the issue
                        if (errorMsg.includes('execution reverted') && !errorMsg.includes('allowance') && !errorMsg.includes('balance') && !errorMsg.includes('slippage')) {
                            console.log(`🔍 Generic revert detected. Checking allowance for ${assetA}...`);
                            
                            // Check if this might be an allowance issue by checking current allowance
                            try {
                                const providerUrls = getAllRpcProviders(network);
                                const rpc_provider = createRetryProviderWithFailover(providerUrls);
                                const tokenContract = new ethers.Contract(assetA, erc20ABI, rpc_provider);
                                
                                // Get the contract address from the transaction
                                const contractAddress = gasError?.transaction?.to || gasError?.error?.transaction?.to;
                                
                                if (contractAddress) {
                                    const allowance = await tokenContract.allowance(poolAddress, contractAddress);
                                    console.log(`Current allowance: ${allowance.toString()}, Required: ${tradeAmount.toString()}`);
                                    
                                    if (allowance.lt(tradeAmount)) {
                                        console.log(`🔑 Allowance insufficient (${allowance.toString()} < ${tradeAmount.toString()}). Attempting auto-approve...`);
                                        
                                        if (apiKey && req.query.platform) {
                                            const approveSuccess = await autoApproveToken(
                                                network,
                                                poolAddress,
                                                assetA,
                                                req.query.platform as string,
                                                apiKey,
                                                provider,
                                                key
                                            );
                                            
                                            if (approveSuccess) {
                                                console.log(`✅ Auto-approve successful. Retrying gas estimation...`);
                                                estimatedGas = await pool.trade(dApp,assetA,assetB,tradeAmount,+slippage,txOptions,true);
                                                
                                                if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
                                                    throw new Error(`Transaction will still fail after approval. May be a balance, slippage, or routing issue.`);
                                                }
                                            } else {
                                                throw new Error('Auto-approve failed. Please approve the token manually.');
                                            }
                                        } else {
                                            throw new Error('Insufficient token allowance. Please approve the token for trading first.');
                                        }
                                    } else {
                                        // Allowance is sufficient, must be another issue
                                        throw new Error('Transaction will revert. This may be due to insufficient balance, slippage, or routing issues. Please check your token balance and try with higher slippage.');
                                    }
                                } else {
                                    throw new Error('Transaction will revert. Unable to determine specific cause. Please check token balance and allowance.');
                                }
                            } catch (checkError) {
                                // If the check itself fails, just throw the original error
                                console.error('Failed to diagnose revert reason:', checkError);
                                throw new Error(`Transaction will fail: ${errorMsg}`);
                            }
                        }
                        // Explicit allowance errors
                        else if (errorMsg.includes('allowance') || errorMsg.includes('exceeds allowance')) {
                            console.log(`🔑 Allowance issue detected for ${assetA}. Attempting auto-approve...`);
                            
                            if (apiKey && req.query.platform) {
                                const approveSuccess = await autoApproveToken(
                                    network,
                                    poolAddress,
                                    assetA,
                                    req.query.platform as string,
                                    apiKey,
                                    provider,
                                    key
                                );
                                
                                if (approveSuccess) {
                                    console.log(`✅ Auto-approve successful. Retrying gas estimation...`);
                                    // Retry gas estimation after approval
                                    estimatedGas = await pool.trade(dApp,assetA,assetB,tradeAmount,+slippage,txOptions,true);
                                    
                                    // Check if it still fails
                                    if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
                                        throw new Error(`Transaction will still fail after approval: ${errorMsg}`);
                                    }
                                } else {
                                    throw new Error('Auto-approve failed. Please approve the token manually.');
                                }
                            } else {
                                throw new Error('Insufficient token allowance. Please approve the token for trading first.');
                            }
                        } else if (errorMsg.includes('insufficient') && errorMsg.includes('balance')) {
                            throw new Error('Insufficient token balance for this trade.');
                        } else {
                            throw new Error(`Transaction will fail: ${errorMsg}`);
                        }
                    }
                    // Only log gas amount, not the whole object
                    const gasValue = (typeof estimatedGas === 'object' && estimatedGas?.toString) ? estimatedGas.toString() : estimatedGas;
                    console.log("estimated gas for odos trade:", gasValue ?? 'null');
                }
                let txOptions2 = await txFees(network,provider,key,estimatedGas);
                
                // Check if wallet has enough gas for this specific transaction
                const estimatedGasCost = ethers.BigNumber.from(txOptions2.gasLimit)
                    .mul(ethers.BigNumber.from(txOptions2.maxFeePerGas));
                
                if (gasBalance.lt(estimatedGasCost)) {
                    const errorMsg = `Insufficient gas for transaction. Need ${ethers.utils.formatEther(estimatedGasCost)} ETH, have ${ethers.utils.formatEther(gasBalance)} ETH. Wallet: ${executingWallet}`;
                    console.error(`❌ ${errorMsg}`);
                    await banWalletForInsufficientGas(executingWallet);
                    res.status(402).send({
                        status: "fail",
                        msg: errorMsg,
                        error_type: "insufficient_gas",
                        executing_wallet: executingWallet,
                        current_balance: ethers.utils.formatEther(gasBalance),
                        required: ethers.utils.formatEther(estimatedGasCost)
                    });
                    return;
                }
                
                gasBumpCount = 0;
                while (true) {
                    try {
                        // Use automatic DEX fallback for trade execution
                        console.log(`[Execute Trade] Using DEX fallback (primary: ${dApp})`);
                        tx = await executeTradeWithFallback({
                            pool,
                            network,
                            primaryDapp: dApp,
                            assetFrom: assetA,
                            assetTo: assetB,
                            amountIn: tradeAmount,
                            slippage: +slippage,
                            txOptions: txOptions2
                        });
                        break;
                    } catch (err) {
                        const msg = (err instanceof Error) ? err.message : String(err);
                        if (msg.includes('replacement transaction underpriced') && gasBumpCount < 3) {
                            console.warn('Replacement transaction underpriced, bumping gas price and retrying...');
                            txOptions2 = {
                                ...txOptions2,
                                maxFeePerGas: txOptions2.maxFeePerGas ? BigNumber.from(txOptions2.maxFeePerGas).mul(110).div(100).toString() : undefined,
                                maxPriorityFeePerGas: txOptions2.maxPriorityFeePerGas ? BigNumber.from(txOptions2.maxPriorityFeePerGas).mul(110).div(100).toString() : undefined
                            };
                            gasBumpCount++;
                            continue;
                        }
                        throw err;
                    }
                }
                
                // Ensure tx is valid before processing
                if (!tx || !tx.hash) {
                    throw new Error('Trade execution failed - no transaction returned');
                }
                
                console.log("trade tx hash:", tx.hash);
                txHashes.push(tx.hash);
                paymentTx = tx;
            }
    }

    if (apiKey && paymentTx) {
        console.log("Sending API payment");
        try {
            await apiPaymentFixed(network, apiKey, paymentTx, 'trade', provider, key, null);
        } catch (paymentError) {
            // If payment fails due to transaction revert, return specific error
            const paymentMsg = (paymentError instanceof Error) ? paymentError.message : JSON.stringify(paymentError);
            if (paymentMsg.includes('status: 0') || paymentMsg.includes('transaction failed')) {
                console.error("Trade transaction reverted - possible causes: slippage exceeded, stale quote, or insufficient allowance");
                throw new Error('Trade transaction failed on-chain. Possible causes: slippage exceeded, ODOS quote expired, or insufficient token allowance. No fee charged.');
            }
            // Re-throw other payment errors
            throw paymentError;
        }
    }

    res.status(200).send({ status: "success", msg: txHashes });
  }
  catch (err) {
    const errorObj = err as any;
    const message = (err instanceof Error) ? err.message : JSON.stringify(err);
    const errorLower = message.toLowerCase();
    
    // Log concise error info instead of full object
    console.error(`❌ Trade failed: ${errorObj?.code || 'UNKNOWN'} - ${message.substring(0, 150)}`);
    if (errorObj?.transactionHash) {
        console.error(`   Transaction hash: ${errorObj.transactionHash}`);
    }
    if (errorObj?.transaction?.from) {
        console.error(`   From wallet: ${errorObj.transaction.from}`);
    }
    
    // Check for specific error types and provide helpful messages
    
    // CALL_EXCEPTION - transaction will revert
    if (errorObj?.code === 'CALL_EXCEPTION' || errorLower.includes('call_exception')) {
        // For generic execution reverts, check if it might be an allowance issue
        if (!errorLower.includes('insufficient allowance') && !errorLower.includes('exceeds allowance') && 
            !errorLower.includes('slippage') && !errorLower.includes('too little received')) {
            
            // We have a generic revert - check if it's an allowance issue
            console.log(`🔍 CALL_EXCEPTION detected. Checking if it's an allowance issue for ${assetA}...`);
            
            if (assetA && poolAddress && tradeAmount && apiKey && req.query.platform && network && provider && key) {
                try {
                    const providerUrls = getAllRpcProviders(network);
                    const rpc_provider = createRetryProviderWithFailover(providerUrls);
                    const tokenContract = new ethers.Contract(assetA, erc20ABI, rpc_provider);
                    
                    // For dHEDGE pools, check allowance from pool to the pool's own address (delegated trading)
                    const allowance = await tokenContract.allowance(poolAddress, poolAddress);
                    console.log(`Current allowance: ${allowance.toString()}, Required: ${tradeAmount.toString()}`);
                    
                    if (allowance.lt(tradeAmount)) {
                        console.log(`🔑 Allowance insufficient! Attempting auto-approve...`);
                        
                        const approveSuccess = await autoApproveToken(
                            network,
                            poolAddress,
                            assetA,
                            req.query.platform as string,
                            apiKey,
                            provider,
                            key
                        );
                        
                        if (approveSuccess) {
                            console.log(`✅ Auto-approve successful! Token approved. Please retry your trade.`);
                            res.status(200).send({ 
                                status: "success", 
                                msg: "Token allowance was insufficient. We've automatically approved it. Please retry your trade now.",
                                action: "retry_trade",
                                approved_token: assetA
                            });
                            return;
                        } else {
                            console.error(`❌ Auto-approve failed`);
                            res.status(400).send({ 
                                status: "fail", 
                                msg: "Transaction will revert: Insufficient token allowance. Auto-approve failed. Please approve the token manually.",
                                error_type: "insufficient_allowance_autoapprove_failed"
                            });
                            return;
                        }
                    } else {
                        console.log(`Allowance is sufficient. CALL_EXCEPTION is due to another reason.`);
                    }
                } catch (checkError) {
                    console.error(`Failed to check/fix allowance:`, checkError);
                    // Fall through to standard error handling
                }
            }
        }
        
        // Try to extract more specific reason from the error
        if (errorLower.includes('insufficient allowance') || errorLower.includes('exceeds allowance')) {
            res.status(400).send({ 
                status: "fail", 
                msg: "Transaction will revert: Insufficient token allowance. Please approve the contract to spend your tokens.",
                error_type: "insufficient_allowance"
            });
        } else if (errorLower.includes('slippage') || errorLower.includes('too little received')) {
            res.status(400).send({ 
                status: "fail", 
                msg: "Transaction will revert: Slippage tolerance exceeded. Try increasing slippage or reducing trade size.",
                error_type: "slippage_exceeded"
            });
        } else {
            res.status(400).send({ 
                status: "fail", 
                msg: "Transaction will revert on-chain. This may be due to contract conditions not being met (slippage, allowance, balance, etc).",
                error_type: "call_exception"
            });
        }
        return;
    }
    
    // Insufficient allowance
    if (errorLower.includes('insufficient allowance') || 
        errorLower.includes('transfer amount exceeds allowance')) {
        res.status(400).send({ 
            status: "fail", 
            msg: "Insufficient token allowance. Please approve the contract to spend your tokens.",
            error_type: "insufficient_allowance"
        });
        return;
    }
    
    // Insufficient balance (insufficient gas for transaction)
    if (errorLower.includes('insufficient funds') || 
        errorLower.includes('insufficient balance') ||
        errorLower.includes('transfer amount exceeds balance')) {
        
        // Try to extract wallet address from error or transaction
        let walletAddr = 'unknown';
        try {
            if (errorObj?.transaction?.from) {
                walletAddr = errorObj.transaction.from;
            } else if (errorObj?.error?.transaction?.from) {
                walletAddr = errorObj.error.transaction.from;
            }
        } catch (e) {
            // Ignore extraction errors
        }
        
        // Check if it's a gas issue (not token balance)
        if (errorLower.includes('gas') || errorLower.includes('intrinsic transaction cost')) {
            console.error(`💰 INSUFFICIENT GAS - Wallet: ${walletAddr}`);
            console.error(`⚠️  This wallet needs to be refilled with gas tokens!`);
            
            // Ban wallet for 15 minutes
            if (walletAddr !== 'unknown') {
                await banWalletForInsufficientGas(walletAddr);
            }
            
            res.status(400).send({ 
                status: "fail", 
                msg: `Insufficient gas in wallet ${walletAddr}. This wallet has been temporarily banned for 15 minutes. Please refill with gas tokens.`,
                error_type: "insufficient_gas",
                wallet_address: walletAddr,
                ban_duration_minutes: 15
            });
        } else {
            // Token balance issue
            res.status(400).send({ 
                status: "fail", 
                msg: "Insufficient token balance to complete trade.",
                error_type: "insufficient_balance"
            });
        }
        return;
    }
    
    // Slippage exceeded
    if (errorLower.includes('slippage') || 
        errorLower.includes('too little received') ||
        errorLower.includes('price impact')) {
        res.status(400).send({ 
            status: "fail", 
            msg: "Slippage tolerance exceeded. Price moved too much during execution. Try increasing slippage or reducing trade size.",
            error_type: "slippage_exceeded"
        });
        return;
    }
    
    // Transaction reverted
    if (errorLower.includes('execution reverted') || 
        errorLower.includes('transaction reverted') ||
        errorLower.includes('transaction failed')) {
        res.status(400).send({ 
            status: "fail", 
            msg: "Transaction reverted on-chain. This may be due to contract conditions not being met. No fee was charged.",
            error_type: "transaction_reverted"
        });
        return;
    }
    
    // RPC provider errors (temporary, retryable)
    if (errorObj?.code === 'SERVER_ERROR' || errorObj?.status === 500) {
        const rpcError = errorObj?.body ? JSON.parse(errorObj.body) : {};
        const traceId = rpcError?.error?.message?.includes('trace-id') 
            ? rpcError.error.message 
            : 'RPC provider temporary error';
        
        res.status(503).send({ 
            status: "fail", 
            msg: `RPC provider error: ${traceId}. Please retry your request in a few seconds.`,
            error_type: "rpc_error",
            retryable: true
        });
        return;
    }
    
    // Generic error
    res.status(400).send({ status: "fail", msg: message });
  }
});

//export const allowanceDelta = async (
//  owner: string,
//  asset: string,
//  spender: string,
//  signer: Wallet
//): Promise<BigNumber> => {
//  const block = await signer.provider.getBlockNumber();
//  const iERC20 = new Contract(asset, IERC20.abi, signer);
//  const [allowanceBefore, allowanceAfter] = await Promise.all(
//    [block - 1, block].map(e =>
//      iERC20.allowance(owner, spender, { blockTag: e })
//    )
//  );
//  return allowanceAfter.sub(allowanceBefore);
//};

//
//implement this endpoints 
//  async claimFees(
//    dapp: Dapp,
//    tokenId: string,
//    options: any = null,
//    estimateGas = false
//  ):
//async addLiquidityV2(
//    dapp: Dapp.VELODROMEV2 | Dapp.RAMSES | Dapp.AERODROME,
//    assetA: string,
//    assetB: string,
//    amountA: BigNumber | string,
//    amountB: BigNumber | string,
//    isStable: boolean,
//    options: any = null,
//    estimateGas = false
//):
//
//removeLiquidityV2(
//    dapp: Dapp.VELODROMEV2 | Dapp.RAMSES | Dapp.AERODROME,
//    assetA: string,
//    assetB: string,
//    amount: BigNumber | string,
//    isStable: boolean,
//    options: any = null,
//    estimateGas = false
//  ):

// Connect to an Ethereum provider (you can use Infura, Alchemy, or any other provider)
//const provider = new ethers.providers.InfuraProvider("mainnet", "YOUR_INFURA_PROJECT_ID");
// or for Alchemy
// const provider = new ethers.providers.AlchemyProvider("mainnet", "YOUR_ALCHEMY_API_KEY");
//traderRouter.post("/getGasPrice", async (req: Request, res: Response) => {
//  try { 
// Get the current gas price
//    const gasPrice = await provider.getGasPrice();
// Convert the gas price from wei to gwei for better readability   
//   const gasPriceInGwei = ethers.utils.formatUnits(gasPrice, "gwei");
//    console.log(`Current gas price: ${gasPriceInGwei} Gwei`);
 // } catch (error) {
//    console.error("Error fetching gas price:", error);
 // }
//}

//tradeRouter.post("/newapprove", async (req, res) => {
//    try {
//        // Set default network to Polygon, but allow override from request
//        let network = Network.POLYGON;
//        if (req.query.network) network = req.query.network;

//        const poolAddress = req.query.pool;
        
        // Manager can be null, in which case the default private key is used
//        let manager = null;
//        if (req.query.manager) manager = req.query.manager;

        // Create a wallet instance for signing
  //      const signer = wallet(network, manager);

        // Check the current allowance
    //    const allowance = await token.allowance(await signer.getAddress(), poolAddress);

      //  if (allowance.lt(ethers.constants.MaxUint256)) {
            // If allowance is insufficient, proceed with the approval
            // Assuming pool.approve is a correct method call in your context, you might need to adjust this
            // Perhaps directly use the `token` contract to call approve if needed
        //    const tx = await token.approve(poolAddress, ethers.constants.MaxUint256);

            // Wait for the transaction to be mined
          //  await tx.wait();

            //res.status(200).send({ status: "success", message: tx.hash });
       // } else {
            // If the current allowance is already sufficient
         //   res.status(200).send({ status: "success", message: "Approval is not required. Allowance is sufficient." });
        //}
    //} catch (err) {
    //    res.status(400).send({ status: "failure", message: err.message });
    //}
//});


// GET /banned-dexs - Check which DEXs are currently banned
tradeRouter.get("/banned-dexs", async (req: Request, res: Response) => {
  try {
    const bannedDexs = await getBannedDexs();
    return res.json({
      status: "success",
      bannedDexs,
      count: bannedDexs.length
    });
  } catch (error: any) {
    console.error("Error getting banned DEXs:", error);
    return sendErrorResponse(res, 500, 500, error?.message || "Failed to get banned DEXs", "BANNED_DEXS_ERROR");
  }
});

// POST /unban-dex - Manually unban a DEX (for testing/emergency)
tradeRouter.post("/unban-dex", async (req: Request, res: Response) => {
  const { network, dex } = req.body;
  
  if (!network || !dex) {
    return sendErrorResponse(res, 400, 400, "Missing network or dex parameter", "VALIDATION_ERROR");
  }
  
  try {
    await unbanDex(network, dex);
    return res.json({
      status: "success",
      message: `Unbanned ${dex} on ${network}`
    });
  } catch (error: any) {
    console.error("Error unbanning DEX:", error);
    return sendErrorResponse(res, 500, 500, error?.message || "Failed to unban DEX", "UNBAN_ERROR");
  }
});


export default tradeRouter;
