import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { getAllRpcProviders } from "../rpc";
import { createRetryProviderWithFailover } from "./RetryProvider";

const ERC20_ABI = [
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)"
];

/**
 * DEX Router Addresses by Network
 * These are the spender addresses that need token approval
 */
const DEX_ROUTER_ADDRESSES: Record<string, Record<string, string>> = {
    // Base Network
    [Network.BASE]: {
        "odos": "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05", // ODOS Router V3
        "1inch": "0x111111125421cA6dc452d289314280a0f8842A65", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x2626664c2603336E57B271c5C0b26F421741e481", // SwapRouter02
        "aavev3": "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5" // AAVE v3 Pool
    },
    
    // Optimism Network
    [Network.OPTIMISM]: {
        "odos": "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05", // ODOS Router V3
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", // SwapRouter02
        "aavev3": "0x794a61358D6845594F94dc1DB02A252b5b4814aD" // AAVE v3 Pool
    },
    
    // Polygon Network
    [Network.POLYGON]: {
        "odos": "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05", // ODOS Router V3
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", // SwapRouter02
        "quickswap": "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // Quickswap Router
        "aavev3": "0x794a61358D6845594F94dc1DB02A252b5b4814aD" // AAVE v3 Pool
    },
    
    // Arbitrum Network
    [Network.ARBITRUM]: {
        "odos": "0x0D05a7D3448512B78fa8A9e46c4872C88C4a0D05", // ODOS Router V3
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", // SwapRouter02
        "aavev3": "0x42EC99A020B78C449d17d93bC4c89e0189B5811d" // AAVE v3 Pool
    }
};

/**
 * Get the router address for a specific DEX on a network
 */
function getRouterAddress(network: Network, dex: string): string | undefined {
    const dexLower = dex.toLowerCase();
    return DEX_ROUTER_ADDRESSES[network]?.[dexLower];
}

/**
 * Check current token allowance for a DEX router
 */
async function checkAllowance(
    network: Network,
    tokenAddress: string,
    ownerAddress: string,
    dex: string
): Promise<ethers.BigNumber> {
    const routerAddress = getRouterAddress(network, dex);
    if (!routerAddress) {
        throw new Error(`Router address not found for ${dex} on ${network}`);
    }
    
    const providerUrls = getAllRpcProviders(network);
    const provider = createRetryProviderWithFailover(providerUrls);
    
    const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, provider);
    const allowance = await tokenContract.allowance(ownerAddress, routerAddress);
    
    return allowance;
}

/**
 * Smart approve wrapper that checks allowance before approving
 * Only approves if current allowance is insufficient
 * Always approves INFINITE (MaxUint256) to avoid needing future approvals
 */
export async function approveIfNeeded(
    network: Network,
    poolAddress: string,
    assetAddress: string,
    amountNeeded: ethers.BigNumber,
    dex: Dapp,
    pool: any
): Promise<boolean> {
    try {
        const dexString = String(dex);
        
        // Check current allowance
        console.log(`🔍 Checking allowance for ${dexString}...`);
        const currentAllowance = await checkAllowance(network, assetAddress, poolAddress, dexString);
        
        // For logging only
        console.log(`Current allowance: ${ethers.utils.formatUnits(currentAllowance, 18)} tokens`);
        console.log(`Amount needed: ${ethers.utils.formatUnits(amountNeeded, 18)} tokens`);
        
        // If allowance is sufficient for THIS trade, skip approval
        if (currentAllowance.gte(amountNeeded)) {
            console.log(`✅ Sufficient allowance for ${dexString} - skipping approval`);
            return true;
        }
        
        // Allowance insufficient, approve INFINITE to avoid future approvals
        console.log(`⚠️ Insufficient allowance for ${dexString} - approving INFINITE (MaxUint256)...`);
        
        const MAX_ALLOWANCE = ethers.constants.MaxUint256;
        const tx = await pool.approve(dex, assetAddress, MAX_ALLOWANCE);
        
        if (!tx) {
            console.log(`✅ Approval handled by SDK for ${dexString}`);
            return true;
        }
        
        console.log(`🔓 Infinite approval tx submitted for ${dexString} | Tx: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`✅ Infinite approval confirmed for ${dexString} | Block: ${receipt.blockNumber}`);
        
        return receipt.status === 1;
    } catch (error: any) {
        if (error?.message?.includes('insufficient funds')) {
            console.error(`❌ Approval failed - insufficient gas in wallet for ${dex}`);
        } else {
            console.error(`❌ Approval failed for ${dex}:`, error?.message || String(error));
        }
        return false;
    }
}

/**
 * Build trade options for specific DEXs
 */
export function buildDexTradeOptions(dex: Dapp, network: Network): any {
    const dexString = String(dex).toLowerCase();
    
    // 1inch requires API key
    if (dexString === '1inch' || dexString === 'oneinch') {
        const apiKey = process.env.ONEINCH_API_KEY;
        if (!apiKey) {
            console.warn('⚠️ ONEINCH_API_KEY not found in environment');
        }
        return {
            apiKey: apiKey || '0ql9wORvT8EXwgIRssuNFc9pYsuf35VW' // Fallback to known key
        };
    }
    
    // ODOS uses referral code (handled in trade-odosv2.ts)
    if (dexString === 'odos') {
        return {};
    }
    
    // Other DEXs don't need special options
    return {};
}
