import { Network } from "@dhedge/v2-sdk";
import { checkContractsWhitelist } from "./vault-guard-cache";

/**
 * Known DEX router addresses by network
 */
const DEX_ROUTER_ADDRESSES: Record<string, Record<string, string>> = {
    // Optimism Network
    [Network.OPTIMISM]: {
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582",
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
    },

    // Base Network
    [Network.BASE]: {
        "1inch": "0x111111125421cA6dc452d289314280a0f8842A65",
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
        "uniswapV3": "0x2626664c2603336E57B271c5C0b26F421741e481"
    },

    // Polygon Network
    [Network.POLYGON]: {
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582",
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
        "quickswap": "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff"
    },

    // Arbitrum Network
    [Network.ARBITRUM]: {
        "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582",
        "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
        "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
    }
};

/**
 * Get all whitelisted DEXs for a vault (with 24h Redis caching)
 */
export async function getWhitelistedDexsForVault(
    vaultAddress: string,
    network: Network
): Promise<string[]> {
    const dexRouters = DEX_ROUTER_ADDRESSES[network] || {};
    return await checkContractsWhitelist(vaultAddress, dexRouters, network, "dex");
}

/**
 * Filter DEX list to only include whitelisted ones for a vault
 */
export async function filterWhitelistedDexs(
    vaultAddress: string,
    dexList: string[],
    network: Network
): Promise<string[]> {
    const whitelisted = await getWhitelistedDexsForVault(vaultAddress, network);
    return dexList.filter(dex => whitelisted.includes(dex.toLowerCase()));
}
