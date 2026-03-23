import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { tryOdosV2ThenV3 } from "./trade-odosv2";
import { approveIfNeeded, buildDexTradeOptions } from "../utils/dex-approve";
import { isDexBanned, handleDexError } from "../utils/dex-ban";

/**
 * DEX fallback configuration by network
 * Ordered by preference: ODOS -> 1inch -> Kyberswap
 */
const DEX_FALLBACKS: Record<string, Dapp[]> = {
    // Base: ODOS -> 1inch -> Kyberswap (UniswapV3 not supported on Base)
    [Network.BASE]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "kyberswap" as Dapp
    ],
    
    // Optimism: ODOS -> 1inch -> Kyberswap -> UniswapV3
    [Network.OPTIMISM]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "kyberswap" as Dapp,
        "uniswapV3" as Dapp
    ],
    
    // Polygon: ODOS -> 1inch -> Kyberswap -> UniswapV3 -> Quickswap
    [Network.POLYGON]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "kyberswap" as Dapp,
        "uniswapV3" as Dapp,
        "quickswap" as Dapp
    ],
    
    // Arbitrum: ODOS -> 1inch -> Kyberswap -> UniswapV3
    [Network.ARBITRUM]: [
        "odos" as Dapp, 
        "1inch" as Dapp,
        "kyberswap" as Dapp,
        "uniswapV3" as Dapp
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
    
    // Filter out banned DEXs
    const unbannedDexs: Dapp[] = [];
    for (const dex of dexesToTry) {
        const banned = await isDexBanned(network, dex);
        if (!banned) {
            unbannedDexs.push(dex);
        } else {
            console.log(`[Trade Fallback] Skipping ${dex} - currently banned`);
        }
    }
    
    if (unbannedDexs.length === 0) {
        throw new Error(`All DEXs are banned on ${network}. Please wait for bans to expire.`);
    }
    
    dexesToTry = unbannedDexs;
    
    let lastError: any;
    
    for (let i = 0; i < dexesToTry.length; i++) {
        const dex = dexesToTry[i];
        const isLastDex = i === dexesToTry.length - 1;
        
        try {
            console.log(`[Trade Fallback] Attempting ${dex} (${i + 1}/${dexesToTry.length})...`);
            
            // Smart approval: check allowance first, only approve if needed
            try {
                const approved = await approveIfNeeded(
                    network,
                    pool.address,
                    assetFrom,
                    amountIn,
                    dex,
                    pool
                );
                if (!approved) {
                    console.warn(`[Trade Fallback] Approval failed for ${dex}, will try trade anyway`);
                }
            } catch (approvalError: any) {
                console.warn(`[Trade Fallback] Could not approve for ${dex}:`, approvalError?.message || String(approvalError));
                // Continue anyway - the trade might still work if already approved
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
                // Use standard pool.trade with DEX-specific options
                const dexOptions = buildDexTradeOptions(dex, network);
                return await pool.trade(dex, assetFrom, assetTo, amountIn, slippage, txOptions, estimateGasOnly, dexOptions);
            }
        } catch (error: any) {
            const errorMsg = error?.message || String(error);
            console.error(`[Trade Fallback] ${dex} failed: ${errorMsg.substring(0, 100)}`);
            
            // Check if DEX should be banned based on error
            await handleDexError(network, dex, error);
            
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
    
    // Filter out banned DEXs
    const unbannedDexs: Dapp[] = [];
    for (const dex of dexesToTry) {
        const banned = await isDexBanned(network, dex);
        if (!banned) {
            unbannedDexs.push(dex);
        } else {
            console.log(`[Execute Trade Fallback] Skipping ${dex} - currently banned`);
        }
    }
    
    if (unbannedDexs.length === 0) {
        throw new Error(`All DEXs are banned on ${network}. Please wait for bans to expire.`);
    }
    
    dexesToTry = unbannedDexs;
    
    let lastError: any;
    
    for (let i = 0; i < dexesToTry.length; i++) {
        const dex = dexesToTry[i];
        const isLastDex = i === dexesToTry.length - 1;
        
        try {
            console.log(`[Execute Trade Fallback] Attempting ${dex} (${i + 1}/${dexesToTry.length})...`);
            
            // Smart approval: check allowance first, only approve if needed
            try {
                const approved = await approveIfNeeded(
                    network,
                    pool.address,
                    assetFrom,
                    amountIn,
                    dex,
                    pool
                );
                if (!approved) {
                    console.warn(`[Execute Trade Fallback] Approval failed for ${dex}, will try trade anyway`);
                }
            } catch (approvalError: any) {
                console.warn(`[Execute Trade Fallback] Could not approve for ${dex}:`, approvalError?.message || String(approvalError));
                // Continue anyway - the trade might still work if already approved
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
                // Use standard pool.trade with DEX-specific options (execution mode)
                const dexOptions = buildDexTradeOptions(dex, network);
                return await pool.trade(dex, assetFrom, assetTo, amountIn, slippage, txOptions, false, dexOptions);
            }
        } catch (error: any) {
            const errorMsg = error?.message || String(error);
            console.error(`[Execute Trade Fallback] ${dex} failed: ${errorMsg.substring(0, 100)}`);
            
            // Check if DEX should be banned based on error
            await handleDexError(network, dex, error);
            
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
