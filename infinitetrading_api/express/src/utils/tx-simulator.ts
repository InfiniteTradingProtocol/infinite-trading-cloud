import { ethers } from "ethers";
import { createRetryProviderWithFailover } from "./RetryProvider";
import { getAllRpcProviders } from "../rpc";
import { Network } from "@dhedge/v2-sdk";

/**
 * Simulates a transaction before execution using eth_call (callStatic)
 * This allows us to detect reverts without spending gas
 * 
 * @param tx - The populated transaction object to simulate
 * @param signer - The wallet/signer that will send the transaction
 * @param network - The network to use for the simulation
 * @param provider - Optional specific provider to use
 * @returns Object with success status and any error details
 */
export async function simulateTransaction(
    tx: ethers.providers.TransactionRequest,
    signer: ethers.Wallet,
    network: Network,
    provider?: string | ethers.providers.Provider | null
): Promise<{ success: boolean; error?: string; errorCode?: string }> {
    try {
        console.log(`🔍 Simulating transaction before execution...`);
        
        // Get provider
        let rpc_provider: ethers.providers.Provider;
        if (provider && typeof provider === 'object' && 'getNetwork' in provider) {
            rpc_provider = provider;
        } else {
            const providerUrls = getAllRpcProviders(network);
            rpc_provider = createRetryProviderWithFailover(providerUrls);
        }
        
        // Connect signer to provider
        const connectedSigner = signer.connect(rpc_provider);
        
        // Prepare transaction for simulation
        const simulationTx = {
            ...tx,
            from: await connectedSigner.getAddress()
        };
        
        // Use callStatic to simulate the transaction
        // This will throw if the transaction would revert
        await rpc_provider.call(simulationTx);
        
        console.log(`✅ Transaction simulation successful - transaction will not revert`);
        return { success: true };
        
    } catch (error: any) {
        const errorMsg = error?.message || error?.reason || String(error);
        const errorCode = error?.code || 'SIMULATION_FAILED';
        
        console.error(`❌ Transaction simulation failed: ${errorMsg.substring(0, 200)}`);
        
        // Parse common revert reasons
        let friendlyError = errorMsg;
        
        if (errorMsg.includes('insufficient allowance') || errorMsg.includes('exceeds allowance')) {
            friendlyError = 'Insufficient token allowance. Approve the token before trading.';
        } else if (errorMsg.includes('insufficient balance') || errorMsg.includes('transfer amount exceeds balance')) {
            friendlyError = 'Insufficient token balance for this trade.';
        } else if (errorMsg.includes('slippage') || errorMsg.includes('too little received')) {
            friendlyError = 'Slippage tolerance too low. The price has moved unfavorably.';
        } else if (errorMsg.includes('expired') || errorMsg.includes('deadline')) {
            friendlyError = 'Transaction deadline expired. Quote is stale.';
        } else if (errorMsg.includes('liquidity') || errorMsg.includes('K')) {
            friendlyError = 'Insufficient liquidity for this trade size.';
        } else if (errorMsg.includes('execution reverted')) {
            // Generic revert - could be many things
            friendlyError = 'Transaction would revert. Check allowance, balance, slippage, and liquidity.';
        }
        
        return { 
            success: false, 
            error: friendlyError,
            errorCode 
        };
    }
}

/**
 * Simulates a contract method call before execution
 * Useful for testing specific contract interactions
 * 
 * @param contract - The ethers Contract instance
 * @param method - The method name to call
 * @param args - Arguments to pass to the method
 * @param overrides - Optional transaction overrides (value, gasLimit, etc)
 * @returns Object with success status and return value or error
 */
export async function simulateContractCall(
    contract: ethers.Contract,
    method: string,
    args: any[],
    overrides?: ethers.CallOverrides
): Promise<{ success: boolean; result?: any; error?: string }> {
    try {
        console.log(`🔍 Simulating contract call: ${method}(${args.join(', ')})`);
        
        // Use callStatic to simulate the contract call
        const result = await contract.callStatic[method](...args, overrides || {});
        
        console.log(`✅ Contract call simulation successful`);
        return { success: true, result };
        
    } catch (error: any) {
        const errorMsg = error?.message || error?.reason || String(error);
        console.error(`❌ Contract call simulation failed: ${errorMsg.substring(0, 200)}`);
        
        return { 
            success: false, 
            error: errorMsg 
        };
    }
}

/**
 * Simulates a dHEDGE pool trade before execution
 * Uses the SDK's gasEstimation feature which internally uses eth_call
 * 
 * @param pool - The dHEDGE pool instance
 * @param dapp - The DEX to use
 * @param assetFrom - Token to sell
 * @param assetTo - Token to buy
 * @param amount - Amount to trade
 * @param slippage - Slippage tolerance (e.g., 1 for 1%)
 * @param txOptions - Transaction options
 * @returns Object with success status and gas estimate or error
 */
export async function simulatePoolTrade(
    pool: any,
    dapp: any,
    assetFrom: string,
    assetTo: string,
    amount: ethers.BigNumber,
    slippage: number,
    txOptions: any
): Promise<{ success: boolean; gasEstimate?: string; error?: string; errorDetails?: any }> {
    try {
        console.log(`🔍 Simulating pool trade via ${dapp}...`);
        console.log(`   From: ${assetFrom} | To: ${assetTo} | Amount: ${amount.toString()}`);
        
        // Use the SDK's gas estimation (which does eth_call simulation)
        const estimatedGas = await pool.trade(dapp, assetFrom, assetTo, amount, slippage, txOptions, true);
        
        // Check if gas estimation returned an error
        if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
            const gasError = (estimatedGas as any).gasEstimationError;
            const errorMsg = gasError?.message || gasError?.reason || String(gasError);
            
            console.error(`❌ Trade simulation failed: ${errorMsg.substring(0, 200)}`);
            
            return {
                success: false,
                error: errorMsg,
                errorDetails: gasError
            };
        }
        
        console.log(`✅ Trade simulation successful - estimated gas: ${estimatedGas}`);
        return { 
            success: true, 
            gasEstimate: estimatedGas?.toString() || estimatedGas 
        };
        
    } catch (error: any) {
        const errorMsg = error?.message || error?.reason || String(error);
        console.error(`❌ Trade simulation failed: ${errorMsg.substring(0, 200)}`);
        
        return {
            success: false,
            error: errorMsg,
            errorDetails: error
        };
    }
}

/**
 * Estimates gas for a transaction with simulation
 * Returns null if simulation fails (transaction would revert)
 * 
 * @param tx - The transaction to estimate gas for
 * @param signer - The wallet/signer
 * @param network - The network
 * @param provider - Optional provider
 * @returns Gas estimate as BigNumber or null if simulation fails
 */
export async function estimateGasWithSimulation(
    tx: ethers.providers.TransactionRequest,
    signer: ethers.Wallet,
    network: Network,
    provider?: string | ethers.providers.Provider | null
): Promise<ethers.BigNumber | null> {
    try {
        // First simulate to check if it will revert
        const simulation = await simulateTransaction(tx, signer, network, provider);
        
        if (!simulation.success) {
            console.error(`⛔ Gas estimation skipped - simulation failed: ${simulation.error}`);
            return null;
        }
        
        // Get provider
        let rpc_provider: ethers.providers.Provider;
        if (provider && typeof provider === 'object' && 'getNetwork' in provider) {
            rpc_provider = provider;
        } else {
            const providerUrls = getAllRpcProviders(network);
            rpc_provider = createRetryProviderWithFailover(providerUrls);
        }
        
        // Now estimate gas
        const connectedSigner = signer.connect(rpc_provider);
        const gasEstimate = await connectedSigner.estimateGas(tx);
        
        // Add 20% buffer for safety
        const gasWithBuffer = gasEstimate.mul(120).div(100);
        
        console.log(`⛽ Gas estimate: ${gasEstimate.toString()} (with buffer: ${gasWithBuffer.toString()})`);
        
        return gasWithBuffer;
        
    } catch (error: any) {
        console.error(`❌ Gas estimation failed:`, error?.message || String(error));
        return null;
    }
}
