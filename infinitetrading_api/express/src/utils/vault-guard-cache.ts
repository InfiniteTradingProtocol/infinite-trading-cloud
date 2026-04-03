import { Network, ethers } from "@dhedge/v2-sdk";
import { getAllRpcProviders } from "../rpc";
import { createRetryProviderWithFailover } from "./RetryProvider";
import { getRedis } from "../lib/redis";

const CACHE_TTL = 24 * 60 * 60; // 24 hours
const REDIS_KEY_PREFIX = "vault:guard:";

/**
 * ABI for vault guard queries
 */
const POOL_LOGIC_ABI = [
    "function poolManagerLogic() view returns (address)"
];

const POOL_MANAGER_LOGIC_ABI = [
    "function contractGuard() view returns (address)"
];

const CONTRACT_GUARD_ABI = [
    "function isContractGuarded(address contractAddress) view returns (bool)",
    "function isAssetSupported(address asset) view returns (bool)"
];

/**
 * Get the guard contract address for a vault (cached)
 */
async function getVaultGuardAddress(
    vaultAddress: string,
    network: Network
): Promise<string | null> {
    const cacheKey = `${REDIS_KEY_PREFIX}guardaddress:${network}:${vaultAddress.toLowerCase()}`;
    
    try {
        const redis = await getRedis();
        const cached = await redis.get(cacheKey);
        if (cached) {
            return cached;
        }
    } catch (error) {
        console.warn("Redis guard address check failed:", error);
    }
    
    // Query on-chain
    try {
        const providerUrls = getAllRpcProviders(network);
        const provider = createRetryProviderWithFailover(providerUrls);
        
        const poolLogic = new ethers.Contract(vaultAddress, POOL_LOGIC_ABI, provider);
        const poolManagerAddress = await poolLogic.poolManagerLogic();
        
        if (!poolManagerAddress || poolManagerAddress === ethers.constants.AddressZero) {
            return null;
        }
        
        const poolManager = new ethers.Contract(
            poolManagerAddress,
            POOL_MANAGER_LOGIC_ABI,
            provider
        );
        const guardAddress = await poolManager.contractGuard();
        
        if (!guardAddress || guardAddress === ethers.constants.AddressZero) {
            return null;
        }
        
        // Cache for 24 hours
        try {
            const redis = await getRedis();
            await redis.setEx(cacheKey, CACHE_TTL, guardAddress);
        } catch (error) {
            console.warn("Failed to cache guard address:", error);
        }
        
        return guardAddress;
    } catch (error) {
        console.error("Error getting vault guard address:", error);
        return null;
    }
}

/**
 * Check if contracts are whitelisted in vault guard
 */
export async function checkContractsWhitelist(
    vaultAddress: string,
    contractAddresses: Record<string, string>, // { name: address }
    network: Network,
    cacheType: string // "dex", "lending", "token", etc.
): Promise<string[]> {
    const cacheKey = `${REDIS_KEY_PREFIX}${cacheType}:${network}:${vaultAddress.toLowerCase()}`;
    
    // Check cache first
    try {
        const redis = await getRedis();
        const cached = await redis.get(cacheKey);
        
        if (cached) {
            const whitelisted = JSON.parse(cached);
            console.log(`✅ [${cacheType}] Using cached whitelist for ${vaultAddress}: ${whitelisted.join(", ")}`);
            return whitelisted;
        }
    } catch (error) {
        console.warn(`[${cacheType}] Redis cache check failed:`, error);
    }
    
    // Cache miss - query on-chain
    const guardAddress = await getVaultGuardAddress(vaultAddress, network);
    
    if (!guardAddress) {
        console.log(`⚠️ [${cacheType}] No guard found for vault ${vaultAddress} - assuming all allowed`);
        const allNames = Object.keys(contractAddresses);
        
        // Cache the result
        try {
            const redis = await getRedis();
            await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(allNames));
        } catch (error) {
            console.warn(`[${cacheType}] Failed to cache:`, error);
        }
        
        return allNames;
    }
    
    const providerUrls = getAllRpcProviders(network);
    const provider = createRetryProviderWithFailover(providerUrls);
    const guard = new ethers.Contract(guardAddress, CONTRACT_GUARD_ABI, provider);
    
    const whitelisted: string[] = [];
    console.log(`🔍 [${cacheType}] Checking whitelist for vault ${vaultAddress}...`);
    
    for (const [name, address] of Object.entries(contractAddresses)) {
        try {
            const isGuarded = await guard.isContractGuarded(address);
            if (isGuarded) {
                whitelisted.push(name);
                console.log(`  ✅ ${name} is whitelisted`);
            } else {
                console.log(`  ❌ ${name} is NOT whitelisted`);
            }
        } catch (error) {
            console.error(`  ⚠️ Error checking ${name}:`, error);
        }
    }
    
    console.log(`📋 [${cacheType}] Whitelisted: ${whitelisted.join(", ") || "none"}`);
    
    // Cache for 24 hours
    try {
        const redis = await getRedis();
        await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(whitelisted));
        console.log(`💾 [${cacheType}] Cached whitelist (expires in 24h)`);
    } catch (error) {
        console.warn(`[${cacheType}] Failed to cache:`, error);
    }
    
    return whitelisted;
}

/**
 * Check if assets are supported in vault guard
 */
export async function checkAssetsWhitelist(
    vaultAddress: string,
    assetAddresses: Record<string, string>, // { symbol: address }
    network: Network
): Promise<string[]> {
    const cacheKey = `${REDIS_KEY_PREFIX}assets:${network}:${vaultAddress.toLowerCase()}`;
    
    // Check cache first
    try {
        const redis = await getRedis();
        const cached = await redis.get(cacheKey);
        
        if (cached) {
            const whitelisted = JSON.parse(cached);
            console.log(`✅ [Assets] Using cached whitelist for ${vaultAddress}: ${whitelisted.join(", ")}`);
            return whitelisted;
        }
    } catch (error) {
        console.warn("[Assets] Redis cache check failed:", error);
    }
    
    // Cache miss - query on-chain
    const guardAddress = await getVaultGuardAddress(vaultAddress, network);
    
    if (!guardAddress) {
        console.log(`⚠️ [Assets] No guard found for vault ${vaultAddress} - assuming all allowed`);
        const allSymbols = Object.keys(assetAddresses);
        
        // Cache the result
        try {
            const redis = await getRedis();
            await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(allSymbols));
        } catch (error) {
            console.warn("[Assets] Failed to cache:", error);
        }
        
        return allSymbols;
    }
    
    const providerUrls = getAllRpcProviders(network);
    const provider = createRetryProviderWithFailover(providerUrls);
    const guard = new ethers.Contract(guardAddress, CONTRACT_GUARD_ABI, provider);
    
    const whitelisted: string[] = [];
    console.log(`🔍 [Assets] Checking whitelist for vault ${vaultAddress}...`);
    
    for (const [symbol, address] of Object.entries(assetAddresses)) {
        try {
            const isSupported = await guard.isAssetSupported(address);
            if (isSupported) {
                whitelisted.push(symbol);
                console.log(`  ✅ ${symbol} is supported`);
            } else {
                console.log(`  ❌ ${symbol} is NOT supported`);
            }
        } catch (error) {
            console.error(`  ⚠️ Error checking ${symbol}:`, error);
        }
    }
    
    console.log(`📋 [Assets] Whitelisted: ${whitelisted.join(", ") || "none"}`);
    
    // Cache for 24 hours
    try {
        const redis = await getRedis();
        await redis.setEx(cacheKey, CACHE_TTL, JSON.stringify(whitelisted));
        console.log(`💾 [Assets] Cached whitelist (expires in 24h)`);
    } catch (error) {
        console.warn("[Assets] Failed to cache:", error);
    }
    
    return whitelisted;
}

/**
 * Manually clear cache for a vault (useful for testing or when guard is updated)
 */
export async function clearVaultGuardCache(
    vaultAddress: string,
    network: Network
): Promise<void> {
    try {
        const redis = await getRedis();
        const pattern = `${REDIS_KEY_PREFIX}*:${network}:${vaultAddress.toLowerCase()}`;
        const keys = await redis.keys(pattern);
        
        if (keys.length > 0) {
            await redis.del(...keys);
            console.log(`🗑️ Cleared ${keys.length} cache entries for vault ${vaultAddress}`);
        }
    } catch (error) {
        console.error("Error clearing vault guard cache:", error);
    }
}
