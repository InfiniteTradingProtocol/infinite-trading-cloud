import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { tryOdosV2ThenV3 } from "./trade-odosv2";
import { getAllRpcProviders } from "../rpc";
import { createRetryProviderWithFailover } from "../utils/RetryProvider";

const erc20ABI = JSON.stringify([
    {"constant":true,"inputs":[],"name":"name","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},
    {"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},
    {"constant":true,"inputs":[],"name":"totalSupply","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},
    {"constant":false,"inputs":[{"name":"_from","type":"address"},{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transferFrom","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},
    {"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"payable":false,"stateMutability":"view","type":"function"},
    {"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},
    {"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},
    {"constant":false,"inputs":[{"name":"_to","type":"address"},{"name":"_value","type":"uint256"}],"name":"transfer","outputs":[{"name":"","type":"bool"}],"payable":false,"stateMutability":"nonpayable","type":"function"},
    {"constant":true,"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},
    {"payable":true,"stateMutability":"payable","type":"fallback"},
    {"anonymous":false,"inputs":[{"indexed":true,"name":"owner","type":"address"},{"indexed":true,"name":"spender","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Approval","type":"event"},
    {"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Transfer","type":"event"}
]);

/**
 * Auto-approve token for a specific DEX
 */
async function autoApproveDexToken(
    network: Network,
    poolAddress: string,
    assetAddress: string,
    dex: Dapp,
    pool: any
): Promise<boolean> {
    try {
        console.log(`🔓 Auto-approving ${assetAddress} for ${dex}...`);
        
        const MAX_ALLOWANCE = ethers.constants.MaxUint256;
        
        // Use pool's approve method directly
        const tx = await pool.approve(dex, assetAddress, MAX_ALLOWANCE);
        console.log(`✅ Auto-approve tx submitted for ${dex}: ${tx.hash}`);
        
        const receipt = await tx.wait();
        console.log(`✅ Auto-approve confirmed for ${dex} | Block: ${receipt.blockNumber} | Status: ${receipt.status}`);
        
        return receipt.status === 1;
    } catch (error: any) {
        console.error(`❌ Auto-approve failed for ${dex}:`, error?.message || String(error));
        return false;
    }
}

/**
 * DEX fallback configuration by network
 * Ordered by preference: native DEXs first, then popular alternatives
 */
const DEX_FALLBACKS: Record<string, Dapp[]> = {
    // Base: ODOS -> 1inch -> UniswapV3 -> Balancer -> SushiSwap
    [Network.BASE]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "uniswapV3" as Dapp, 
        "balancer" as Dapp,
        "sushiswap" as Dapp
    ],
    
    // Optimism: ODOS -> 1inch -> UniswapV3 -> Balancer -> SushiSwap
    [Network.OPTIMISM]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "uniswapV3" as Dapp, 
        "balancer" as Dapp,
        "sushiswap" as Dapp
    ],
    
    // Polygon: ODOS -> 1inch -> UniswapV3 -> Quickswap -> Balancer -> SushiSwap
    [Network.POLYGON]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "uniswapV3" as Dapp,
        "quickswap" as Dapp,
        "balancer" as Dapp,
        "sushiswap" as Dapp
    ],
    
    // Arbitrum: ODOS -> 1inch -> UniswapV3 -> Ramses -> Balancer -> SushiSwap
    [Network.ARBITRUM]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "uniswapV3" as Dapp,
        "ramses" as Dapp,
        "ramsescL" as Dapp,
        "balancer" as Dapp,
        "sushiswap" as Dapp
    ],
};

/**
 * Attempts to trade using primary DEX with automatic fallback to alternatives
 */
export async function tradeWithFallback(params: {
    pool: any;
    network: Network;
    primaryDapp: Dapp;
    assetFrom: string;
    assetTo: string;
    amountIn: any;
    slippage: number;
    txOptions: any;
    estimateGasOnly: boolean;
}): Promise<any> {
    const { pool, network, primaryDapp, assetFrom, assetTo, amountIn, slippage, txOptions, estimateGasOnly } = params;
    
    // Get fallback chain for this network
    const fallbackChain = DEX_FALLBACKS[network] || ["odos" as Dapp, "uniswapV3" as Dapp];
    
    // If primary DEX is in the chain, use that order; otherwise prepend it
    let dexesToTry: Dapp[];
    if (fallbackChain.includes(primaryDapp)) {
        dexesToTry = fallbackChain;
    } else {
        dexesToTry = [primaryDapp, ...fallbackChain];
    }
    
    // Remove duplicates while preserving order
    dexesToTry = [...new Set(dexesToTry)];
    
    let lastError: any;
    
    for (let i = 0; i < dexesToTry.length; i++) {
        const dex = dexesToTry[i];
        const isLastDex = i === dexesToTry.length - 1;
        
        try {
            console.log(`[Trade Fallback] Attempting ${dex} (${i + 1}/${dexesToTry.length})...`);
            
            // Check and ensure token allowance for this specific DEX
            try {
                const providerUrls = getAllRpcProviders(network);
                const rpc_provider = createRetryProviderWithFailover(providerUrls);
                const tokenContract = new ethers.Contract(assetFrom, erc20ABI, rpc_provider);
                
                const poolAddress = pool.address;
                const allowance = await tokenContract.allowance(poolAddress, poolAddress);
                
                if (allowance.lt(amountIn)) {
                    console.log(`[Trade Fallback] Insufficient allowance for ${dex}. Approving...`);
                    const approved = await autoApproveDexToken(network, poolAddress, assetFrom, dex, pool);
                    if (!approved) {
                        throw new Error(`Failed to approve token for ${dex}`);
                    }
                    // Wait a moment for approval to propagate
                    await new Promise(resolve => setTimeout(resolve, 2000));
                }
            } catch (allowanceError) {
                console.warn(`[Trade Fallback] Could not check/approve allowance for ${dex}:`, allowanceError);
                // Continue anyway - the trade might still work
            }
            
            if (dex === "odos" as Dapp) {
                // Use ODOS with v2->v3 fallback
                return await tryOdosV2ThenV3({
                    pool,
                    assetFrom,
                    assetTo,
                    amountIn,
                    slippage,
                    txOptions,
                    estimateGasOnly
                });
            } else {
                // Use standard pool.trade for other DEXs
                return await pool.trade(dex, assetFrom, assetTo, amountIn, slippage, txOptions, estimateGasOnly);
            }
        } catch (error: any) {
            const errorMsg = error?.message || String(error);
            console.error(`[Trade Fallback] ${dex} failed: ${errorMsg.substring(0, 100)}`);
            
            lastError = error;
            
            // If this is not the last DEX, try the next one
            if (!isLastDex) {
                console.log(`[Trade Fallback] Falling back to next DEX...`);
                continue;
            }
        }
    }
    
    // All DEXs failed
    console.error(`[Trade Fallback] All DEXs failed for ${network}`);
    throw lastError || new Error("All DEX attempts failed");
}

/**
 * Executes actual trade (non-estimate) with fallback
 */
export async function executeTradeWithFallback(params: {
    pool: any;
    network: Network;
    primaryDapp: Dapp;
    assetFrom: string;
    assetTo: string;
    amountIn: any;
    slippage: number;
    txOptions: any;
}): Promise<any> {
    const { pool, network, primaryDapp, assetFrom, assetTo, amountIn, slippage, txOptions } = params;
    
    // Get fallback chain for this network
    const fallbackChain = DEX_FALLBACKS[network] || ["odos" as Dapp, "uniswapV3" as Dapp];
    
    // If primary DEX is in the chain, use that order; otherwise prepend it
    let dexesToTry: Dapp[];
    if (fallbackChain.includes(primaryDapp)) {
        dexesToTry = fallbackChain;
    } else {
        dexesToTry = [primaryDapp, ...fallbackChain];
    }
    
    // Remove duplicates while preserving order
    dexesToTry = [...new Set(dexesToTry)];
    
    let lastError: any;
    
    for (let i = 0; i < dexesToTry.length; i++) {
        const dex = dexesToTry[i];
        const isLastDex = i === dexesToTry.length - 1;
        
        try {
            console.log(`[Execute Trade Fallback] Attempting ${dex} (${i + 1}/${dexesToTry.length})...`);
            
            // Check and ensure token allowance for this specific DEX
            try {
                const providerUrls = getAllRpcProviders(network);
                const rpc_provider = createRetryProviderWithFailover(providerUrls);
                const tokenContract = new ethers.Contract(assetFrom, erc20ABI, rpc_provider);
                
                const poolAddress = pool.address;
                const allowance = await tokenContract.allowance(poolAddress, poolAddress);
                
                if (allowance.lt(amountIn)) {
                    console.log(`[Execute Trade Fallback] Insufficient allowance for ${dex}. Approving...`);
                    const approved = await autoApproveDexToken(network, poolAddress, assetFrom, dex, pool);
                    if (!approved) {
                        throw new Error(`Failed to approve token for ${dex}`);
                    }
                    // Wait a moment for approval to propagate
                    await new Promise(resolve => setTimeout(resolve, 2000));
                }
            } catch (allowanceError) {
                console.warn(`[Execute Trade Fallback] Could not check/approve allowance for ${dex}:`, allowanceError);
                // Continue anyway - the trade might still work
            }
            
            if (dex === "odos" as Dapp) {
                // Use ODOS with v2->v3 fallback (execution mode)
                return await tryOdosV2ThenV3({
                    pool,
                    assetFrom,
                    assetTo,
                    amountIn,
                    slippage,
                    txOptions,
                    estimateGasOnly: false
                });
            } else {
                // Use standard pool.trade for other DEXs (execution mode)
                return await pool.trade(dex, assetFrom, assetTo, amountIn, slippage, txOptions, false);
            }
        } catch (error: any) {
            const errorMsg = error?.message || String(error);
            console.error(`[Execute Trade Fallback] ${dex} failed: ${errorMsg.substring(0, 100)}`);
            
            lastError = error;
            
            // If this is not the last DEX, try the next one
            if (!isLastDex) {
                console.log(`[Execute Trade Fallback] Falling back to next DEX...`);
                continue;
            }
        }
    }
    
    // All DEXs failed
    console.error(`[Execute Trade Fallback] All DEXs failed for ${network}`);
    throw lastError || new Error("All DEX attempts failed");
}
