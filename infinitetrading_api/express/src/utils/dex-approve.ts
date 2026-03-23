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
        "odos": "0x19cEeAd7105607Cd444F5ad10dd51356436095a1", // ODOS Router V2
        "1inch": "0x111111125421cA6dc452d289314280a0f8842A65", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x2626664c2603336E57B271c5C0b26F421741e481" // SwapRouter02
    },
    
    // Optimism Network
    [Network.OPTIMISM]: {
        "odos": "0xCa423977156BB05b13A2BA3b76Bc5419E2fE9680", // ODOS Router V2
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" // SwapRouter02
    },
    
    // Polygon Network
    [Network.POLYGON]: {
        "odos": "0x4E3288c9ca110bCC82bf38F09A7b425c095d92Bf", // ODOS Router V2
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45", // SwapRouter02
        "quickswap": "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff" // Quickswap Router
    },
    
    // Arbitrum Network
    [Network.ARBITRUM]: {
        "odos": "0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13", // ODOS Router V2
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582", // 1inch V5 Aggregation Router
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5", // KyberSwap MetaAggregationRouterV2
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45" // SwapRouter02
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
        
        console.log(`Current allowance: ${ethers.utils.formatUnits(currentAllowance, 18)} tokens`);
        console.log(`Amount needed: ${ethers.utils.formatUnits(amountNeeded, 18)} tokens`);
        
        // If allowance is sufficient, skip approval
        if (currentAllowance.gte(amountNeeded)) {
            console.log(`✅ Sufficient allowance for ${dexString} - skipping approval`);
            return true;
        }
        
        // Allowance insufficient, need to approve
        console.log(`⚠️ Insufficient allowance for ${dexString} - approving...`);
        
        const MAX_ALLOWANCE = ethers.constants.MaxUint256;
        const tx = await pool.approve(dex, assetAddress, MAX_ALLOWANCE);
        
        if (!tx) {
            console.log(`✅ Approval handled by SDK for ${dexString}`);
            return true;
        }
        
        console.log(`🔓 Approval tx submitted for ${dexString} | Tx: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`✅ Approval confirmed for ${dexString} | Block: ${receipt.blockNumber}`);
        
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
