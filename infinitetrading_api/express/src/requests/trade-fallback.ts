import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { tryOdosV2ThenV3 } from "./trade-odosv2";
import { approveIfNeeded, buildDexTradeOptions } from "../utils/dex-approve";
import { isDexBanned, handleDexError, isPairNotFoundError, isGuardError } from "../utils/dex-ban";
import { checkGasBalance, banWalletForInsufficientGas } from "./trade";

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
            
            // Check if approval works - if guard rejects, this DEX isn't whitelisted
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
                    console.warn(`[Trade Fallback] Approval failed for ${dex}`);
                    // If approval fails but it's not the last DEX, try next one
                    if (!isLastDex) {
                        console.log(`[Trade Fallback] Trying next DEX due to approval failure...`);
                        continue;
                    }
                }
            } catch (approvalError: any) {
                const approvalMsg = approvalError?.message || String(approvalError);
                
                // Check if this is a guard rejection - means DEX not whitelisted in vault
                if (isGuardError(approvalMsg)) {
                    console.log(`🛡️ [Trade Fallback] ${dex} not whitelisted in vault guard. Skipping to next DEX...`);
                    if (!isLastDex) {
                        continue;
                    } else {
                        throw new Error(`All DEXs failed. Last error: ${dex} not supported by vault guard.`);
                    }
                }
                
                console.warn(`[Trade Fallback] Approval error for ${dex}:`, approvalMsg.substring(0, 100));
                // Try trade anyway - might already be approved
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
            
            // Log if this is a pair/liquidity issue for better debugging
            if (isPairNotFoundError(errorMsg)) {
                console.log(`🔍 [Trade Fallback] ${dex} doesn't have pair ${assetFrom}-${assetTo} or insufficient liquidity. Trying next DEX...`);
            }
            
            // Log if this is a guard rejection
            if (isGuardError(errorMsg)) {
                console.log(`🛡️ [Trade Fallback] ${dex} rejected by vault guard. This trade may not be allowed in this vault. Trying next DEX...`);
            }
            
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
            
            // Check if approval works - if guard rejects, this DEX isn't whitelisted
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
                    console.warn(`[Execute Trade Fallback] Approval failed for ${dex}`);
                    // If approval fails but it's not the last DEX, try next one
                    if (!isLastDex) {
                        console.log(`[Execute Trade Fallback] Trying next DEX due to approval failure...`);
                        continue;
                    }
                }
            } catch (approvalError: any) {
                const approvalMsg = approvalError?.message || String(approvalError);
                
                // Check if this is a guard rejection - means DEX not whitelisted in vault
                if (isGuardError(approvalMsg)) {
                    console.log(`🛡️ [Execute Trade Fallback] ${dex} not whitelisted in vault guard. Skipping to next DEX...`);
                    if (!isLastDex) {
                        continue;
                    } else {
                        throw new Error(`All DEXs failed. Last error: ${dex} not supported by vault guard.`);
                    }
                }
                
                console.warn(`[Execute Trade Fallback] Approval error for ${dex}:`, approvalMsg.substring(0, 100));
                // Try trade anyway - might already be approved
            }
            
            // CRITICAL: Check gas balance BEFORE executing trade to prevent wasting customer gas
            // Use txOptions.gasLimit if available, otherwise use conservative 1M gas estimate with 1.5x safety margin
            const baseGasLimit = txOptions.gasLimit || ethers.BigNumber.from(1000000);
            const safeGasLimit = baseGasLimit.mul(150).div(100); // 1.5x safety margin
            const maxFeePerGas = txOptions.maxFeePerGas || ethers.BigNumber.from(0);
            
            const gasCheck = await checkGasBalance(
                network,
                pool.signer.address,
                safeGasLimit, // Use conservative estimate with safety margin
                maxFeePerGas,
                `${dex}-fallback`,
                undefined // Let it fetch fresh balance
            );
            
            if (!gasCheck.sufficient) {
                const gasToken = network === Network.POLYGON ? 'MATIC' : 'ETH';
                console.error(
                    `❌ [Execute Trade Fallback] Insufficient gas for ${dex} trade:\n` +
                    `   Balance: ${ethers.utils.formatEther(gasCheck.balance)} ${gasToken}\n` +
                    `   Required (with 1.5x safety margin): ${ethers.utils.formatEther(gasCheck.required)} ${gasToken}\n` +
                    `   🚫 PREVENTING FAILED TRANSACTION - Skipping to next DEX or banning wallet`
                );
                
                // If this is the last DEX, ban the wallet
                if (isLastDex) {
                    await banWalletForInsufficientGas(pool.signer.address);
                    throw new Error(`Insufficient ${gasToken} for trade. Wallet banned for 15 minutes. Balance: ${ethers.utils.formatEther(gasCheck.balance)}, Required: ${ethers.utils.formatEther(gasCheck.required)}`);
                }
                
                // Try next DEX
                console.log(`[Execute Trade Fallback] Trying next DEX due to insufficient gas...`);
                continue;
            }
            
            console.log(`✅ [Execute Trade Fallback] Sufficient gas for ${dex} - proceeding with trade (checked with 1.5x safety margin)...`);
            
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
            
            // Log if this is a pair/liquidity issue for better debugging
            if (isPairNotFoundError(errorMsg)) {
                console.log(`🔍 [Execute Trade Fallback] ${dex} doesn't have pair ${assetFrom}-${assetTo} or insufficient liquidity. Trying next DEX...`);
            }
            
            // Log if this is a guard rejection  
            if (isGuardError(errorMsg)) {
                console.log(`🛡️ [Execute Trade Fallback] ${dex} rejected by vault guard. This trade may not be allowed in this vault. Trying next DEX...`);
            }
            
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
