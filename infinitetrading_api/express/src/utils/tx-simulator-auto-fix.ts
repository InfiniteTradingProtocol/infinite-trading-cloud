import { ethers, Network, Dapp } from "@dhedge/v2-sdk";
import { createRetryProviderWithFailover } from "./RetryProvider";
import { getAllRpcProviders } from "../rpc";
import { approveIfNeeded } from "./dex-approve";

/**
 * Simulation result with diagnostic information
 */
export interface SimulationResult {
    success: boolean;
    error?: string;
    errorCode?: string;
    errorType?: 'allowance' | 'balance' | 'slippage' | 'gas' | 'liquidity' | 'deadline' | 'generic';
    diagnostics?: {
        hasAllowance?: boolean;
        allowanceAmount?: string;
        requiredAmount?: string;
        hasBalance?: boolean;
        balanceAmount?: string;
        hasGas?: boolean;
        gasBalance?: string;
        suggestedSlippage?: number;
    };
    autoFixAttempted?: boolean;
    autoFixSuccess?: boolean;
}

/**
 * Auto-fix options for simulation failures
 */
export interface AutoFixOptions {
    network: Network;
    poolAddress?: string;
    tokenAddress?: string;
    spenderAddress?: string;
    amount?: ethers.BigNumber;
    dapp?: Dapp;
    pool?: any;
    attemptApproval?: boolean;
    maxSlippage?: number;
}

/**
 * Enhanced transaction simulation with automatic issue detection and fixing
 * 
 * @param tx - Transaction to simulate
 * @param signer - Wallet/signer
 * @param network - Network
 * @param provider - Optional provider
 * @param autoFixOptions - Options for automatic fixing
 * @returns Detailed simulation result with diagnostics
 */
export async function simulateTransactionWithAutoFix(
    tx: ethers.providers.TransactionRequest,
    signer: ethers.Wallet,
    network: Network,
    provider?: string | ethers.providers.Provider | null,
    autoFixOptions?: AutoFixOptions
): Promise<SimulationResult> {
    try {
        console.log(`🔍 Simulating transaction with auto-fix enabled...`);
        
        // Get provider
        let rpc_provider: ethers.providers.Provider;
        if (provider && typeof provider === 'object' && 'getNetwork' in provider) {
            rpc_provider = provider;
        } else {
            const providerUrls = getAllRpcProviders(network);
            rpc_provider = createRetryProviderWithFailover(providerUrls);
        }
        
        const connectedSigner = signer.connect(rpc_provider);
        const walletAddress = await connectedSigner.getAddress();
        
        // Prepare transaction for simulation
        const simulationTx = {
            ...tx,
            from: walletAddress
        };
        
        // Try simulation
        try {
            await rpc_provider.call(simulationTx);
            console.log(`✅ Transaction simulation successful`);
            return { success: true };
        } catch (simError: any) {
            // Simulation failed - diagnose and try to fix
            return await diagnoseAndFix(simError, tx, connectedSigner, rpc_provider, network, autoFixOptions);
        }
        
    } catch (error: any) {
        const errorMsg = error?.message || error?.reason || String(error);
        console.error(`❌ Simulation framework error: ${errorMsg}`);
        
        return {
            success: false,
            error: errorMsg,
            errorCode: error?.code || 'SIMULATION_ERROR'
        };
    }
}

/**
 * Diagnose simulation failure and attempt to fix the issue
 */
async function diagnoseAndFix(
    error: any,
    tx: ethers.providers.TransactionRequest,
    signer: ethers.Wallet,
    provider: ethers.providers.Provider,
    network: Network,
    autoFixOptions?: AutoFixOptions
): Promise<SimulationResult> {
    const errorMsg = (error?.message || error?.reason || String(error)).toLowerCase();
    const walletAddress = await signer.getAddress();
    
    console.log(`🔬 Diagnosing simulation failure...`);
    
    const result: SimulationResult = {
        success: false,
        error: error?.message || String(error),
        errorCode: error?.code,
        diagnostics: {}
    };
    
    // 1. Check for ALLOWANCE issues
    if (errorMsg.includes('allowance') || errorMsg.includes('approve') || errorMsg.includes('erc20')) {
        console.log(`🔑 Detected allowance issue`);
        result.errorType = 'allowance';
        
        if (autoFixOptions?.attemptApproval && autoFixOptions.tokenAddress && autoFixOptions.pool && autoFixOptions.dapp) {
            console.log(`🔧 Attempting to fix allowance issue...`);
            result.autoFixAttempted = true;
            
            try {
                const poolAddress = autoFixOptions.poolAddress || autoFixOptions.pool.address;
                const approved = await approveIfNeeded(
                    network,
                    poolAddress,
                    autoFixOptions.tokenAddress,
                    autoFixOptions.amount || ethers.constants.MaxUint256,
                    autoFixOptions.dapp,
                    autoFixOptions.pool
                );
                
                if (approved) {
                    console.log(`✅ Allowance fixed! Retrying simulation...`);
                    result.autoFixSuccess = true;
                    
                    // Retry simulation after fix
                    try {
                        await provider.call({ ...tx, from: walletAddress });
                        console.log(`✅ Transaction simulation successful after auto-fix`);
                        return { success: true, autoFixAttempted: true, autoFixSuccess: true };
                    } catch (retryError: any) {
                        console.warn(`⚠️ Simulation still failing after approval - may need additional fixes`);
                        result.error = `Allowance fixed, but transaction still fails: ${retryError.message}`;
                    }
                } else {
                    result.autoFixSuccess = false;
                    result.error = 'Failed to approve token';
                }
            } catch (fixError: any) {
                console.error(`❌ Auto-fix failed: ${fixError.message}`);
                result.autoFixSuccess = false;
                result.error = `Allowance issue detected but auto-fix failed: ${fixError.message}`;
            }
        } else {
            result.error = 'Insufficient token allowance. Approval required.';
            result.diagnostics!.hasAllowance = false;
        }
        
        return result;
    }
    
    // 2. Check for INSUFFICIENT BALANCE
    if (errorMsg.includes('insufficient balance') || errorMsg.includes('transfer amount exceeds balance')) {
        console.log(`💰 Detected insufficient balance issue`);
        result.errorType = 'balance';
        
        if (autoFixOptions?.tokenAddress) {
            try {
                const tokenContract = new ethers.Contract(
                    autoFixOptions.tokenAddress,
                    ['function balanceOf(address) view returns (uint256)'],
                    provider
                );
                const ownerAddress = autoFixOptions.poolAddress || walletAddress;
                const balance = await tokenContract.balanceOf(ownerAddress);
                
                result.diagnostics!.hasBalance = false;
                result.diagnostics!.balanceAmount = balance.toString();
                result.diagnostics!.requiredAmount = autoFixOptions.amount?.toString() || 'unknown';
                
                result.error = `Insufficient token balance: ${ethers.utils.formatUnits(balance, 18)} available, ${autoFixOptions.amount ? ethers.utils.formatUnits(autoFixOptions.amount, 18) : 'unknown'} required`;
            } catch (e) {
                result.error = 'Insufficient token balance for this transaction';
            }
        } else {
            result.error = 'Insufficient token balance for this transaction';
        }
        
        return result;
    }
    
    // 3. Check for INSUFFICIENT GAS
    if (errorMsg.includes('insufficient funds') && !errorMsg.includes('balance')) {
        console.log(`⛽ Detected insufficient gas issue`);
        result.errorType = 'gas';
        
        try {
            const gasBalance = await provider.getBalance(walletAddress);
            result.diagnostics!.hasGas = false;
            result.diagnostics!.gasBalance = gasBalance.toString();
            
            const gasToken = network === Network.POLYGON ? 'MATIC' : 'ETH';
            result.error = `Insufficient ${gasToken} for gas: ${ethers.utils.formatEther(gasBalance)} ${gasToken} available`;
        } catch (e) {
            result.error = 'Insufficient native token (ETH/MATIC) for gas fees';
        }
        
        return result;
    }
    
    // 4. Check for SLIPPAGE issues
    if (errorMsg.includes('slippage') || errorMsg.includes('too little received') || errorMsg.includes('min return')) {
        console.log(`📉 Detected slippage issue`);
        result.errorType = 'slippage';
        
        const currentSlippage = autoFixOptions?.maxSlippage || 0.5;
        const suggestedSlippage = Math.min(currentSlippage * 2, 5); // Double slippage up to 5%
        
        result.diagnostics!.suggestedSlippage = suggestedSlippage;
        result.error = `Slippage tolerance too low. Current: ${currentSlippage}%, Suggested: ${suggestedSlippage}%`;
        
        return result;
    }
    
    // 5. Check for DEADLINE/EXPIRY issues
    if (errorMsg.includes('expired') || errorMsg.includes('deadline') || errorMsg.includes('stale')) {
        console.log(`⏰ Detected deadline/expiry issue`);
        result.errorType = 'deadline';
        result.error = 'Transaction deadline expired or quote is stale. Get a fresh quote.';
        
        return result;
    }
    
    // 6. Check for LIQUIDITY issues
    if (errorMsg.includes('liquidity') || errorMsg.includes('k') || errorMsg.includes('reserves')) {
        console.log(`🏊 Detected liquidity issue`);
        result.errorType = 'liquidity';
        result.error = 'Insufficient liquidity for this trade size. Try a smaller amount or different DEX.';
        
        return result;
    }
    
    // 7. Generic execution revert
    result.errorType = 'generic';
    result.error = `Transaction would revert: ${error.message || String(error)}`;
    
    console.log(`❓ Generic revert - unable to auto-diagnose`);
    
    return result;
}

/**
 * Simulate a pool trade with auto-fix capabilities
 * 
 * @param pool - dHEDGE pool instance
 * @param dapp - DEX to use
 * @param assetFrom - Token to sell
 * @param assetTo - Token to buy
 * @param amount - Amount to trade
 * @param slippage - Slippage tolerance
 * @param txOptions - Transaction options
 * @param network - Network
 * @param autoFix - Whether to attempt automatic fixes
 * @returns Simulation result with diagnostics
 */
export async function simulatePoolTradeWithAutoFix(
    pool: any,
    dapp: Dapp,
    assetFrom: string,
    assetTo: string,
    amount: ethers.BigNumber,
    slippage: number,
    txOptions: any,
    network: Network,
    autoFix: boolean = true
): Promise<SimulationResult> {
    try {
        console.log(`🔍 Simulating pool trade with auto-fix...`);
        console.log(`   DEX: ${dapp} | Amount: ${amount.toString()} | Slippage: ${slippage}%`);
        
        // Use SDK's gas estimation (which does simulation internally)
        const estimatedGas = await pool.trade(dapp, assetFrom, assetTo, amount, slippage, txOptions, true);
        
        // Check if gas estimation returned an error
        if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
            const gasError = (estimatedGas as any).gasEstimationError;
            
            if (autoFix) {
                // Attempt to diagnose and fix
                const autoFixOptions: AutoFixOptions = {
                    network,
                    poolAddress: pool.address,
                    tokenAddress: assetFrom,
                    amount,
                    dapp,
                    pool,
                    attemptApproval: true,
                    maxSlippage: slippage
                };
                
                // Create a simulated transaction object for diagnosis
                const mockTx = {
                    to: pool.address,
                    data: '0x' // Would be actual calldata
                };
                
                // Use provider from pool if available
                const provider = pool.provider || pool.signer?.provider;
                const signer = pool.signer;
                
                if (provider && signer) {
                    return await diagnoseAndFix(gasError, mockTx, signer, provider, network, autoFixOptions);
                }
            }
            
            return {
                success: false,
                error: gasError?.message || String(gasError),
                errorType: 'generic'
            };
        }
        
        console.log(`✅ Pool trade simulation successful - estimated gas: ${estimatedGas}`);
        return {
            success: true,
            diagnostics: {
                // Could add gas estimate here
            }
        };
        
    } catch (error: any) {
        const errorMsg = error?.message || error?.reason || String(error);
        console.error(`❌ Pool trade simulation failed: ${errorMsg.substring(0, 200)}`);
        
        return {
            success: false,
            error: errorMsg,
            errorType: 'generic'
        };
    }
}
