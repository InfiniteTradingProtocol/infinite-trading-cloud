import { getRedis } from "../lib/redis";
import { Network, Dapp } from "@dhedge/v2-sdk";

const REDIS_KEY_PREFIX = "dex:ban:";
const BAN_DURATION_SECONDS = 24 * 60 * 60; // 24 hours

/**
 * Ban reasons that trigger automatic DEX banning
 * These are specifically DEX/API issues, NOT wallet/gas issues
 */
const BAN_TRIGGERS = [
    "Requests per month exceeded",
    "Monthly quota exceeded",
    "Rate limit exceeded",
    "rate limit",
    "429",
    "Too Many Requests",
    "too many requests",
    "quota",
    "request limit"
];

/**
 * Errors that should NOT trigger a ban (wallet/transaction issues)
 */
const NO_BAN_PATTERNS = [
    "insufficient funds",
    "insufficient balance",
    "insufficient allowance",
    "exceeds allowance",
    "nonce",
    "replacement transaction underpriced",
    "transaction underpriced",
    "gas",
    "slippage",
    "deadline",
    "expired",
    "execution reverted",
    "revert",
    "call exception",
    "network error",
    "timeout",
    "connection refused",
    // Pair existence errors - should trigger fallback, not ban
    "no liquidity",
    "insufficient liquidity",
    "pair not found",
    "pool not found",
    "no pool",
    "pair does not exist",
    "pool does not exist",
    "no route",
    "cannot find route",
    "no path found",
    "token not supported",
    "unsupported token",
    "invalid pair",
    // dHEDGE guard errors - vault configuration issue, not DEX issue
    "guard",
    "not supported",
    "not enabled",
    "not allowed",
    "istxtrackingguard",
    "0x7bf98119" // isTxTrackingGuard() selector
];

/**
 * Check if error message should trigger a DEX ban
 * Only ban for rate limiting / quota issues, NOT wallet/transaction issues
 */
function shouldBanDex(errorMessage: string): boolean {
    const msgLower = errorMessage.toLowerCase();
    
    // First check if it matches any NO_BAN patterns - these take precedence
    const isWalletError = NO_BAN_PATTERNS.some(pattern => msgLower.includes(pattern.toLowerCase()));
    if (isWalletError) {
        return false;
    }
    
    // Only ban if it matches a BAN_TRIGGER (rate limit / quota)
    return BAN_TRIGGERS.some(trigger => msgLower.includes(trigger.toLowerCase()));
}

/**
 * Check if error indicates pair/liquidity doesn't exist on this DEX
 * These errors should trigger immediate fallback to next DEX
 */
export function isPairNotFoundError(errorMessage: string): boolean {
    const msgLower = errorMessage.toLowerCase();
    const pairErrors = [
        "no liquidity",
        "insufficient liquidity",
        "pair not found",
        "pool not found",
        "no pool",
        "pair does not exist",
        "pool does not exist",
        "no route",
        "cannot find route",
        "no path found",
        "token not supported",
        "unsupported token",
        "invalid pair"
    ];
    return pairErrors.some(pattern => msgLower.includes(pattern));
}

/**
 * Check if error indicates dHEDGE guard rejection
 * These usually mean:
 * - Asset not whitelisted in vault
 * - DEX/Contract not approved in guard
 * - Trade violates vault constraints
 */
export function isGuardError(errorMessage: string): boolean {
    const msgLower = errorMessage.toLowerCase();
    const guardErrors = [
        "guard",
        "not supported",
        "not enabled",
        "not allowed",
        "istxtrackingguard",
        "0x7bf98119" // isTxTrackingGuard() selector
    ];
    return guardErrors.some(pattern => msgLower.includes(pattern));
}

/**
 * Ban a DEX for 24 hours
 */
export async function banDex(network: Network, dex: string, reason: string): Promise<void> {
    try {
        const redis = await getRedis();
        const key = `${REDIS_KEY_PREFIX}${network}:${dex.toLowerCase()}`;
        
        await redis.setEx(key, BAN_DURATION_SECONDS, JSON.stringify({
            bannedAt: new Date().toISOString(),
            reason: reason,
            expiresIn: BAN_DURATION_SECONDS
        }));
        
        console.log(`🚫 Banned ${dex} on ${network} for 24 hours. Reason: ${reason}`);
    } catch (error: any) {
        console.error(`Failed to ban DEX in Redis:`, error?.message || String(error));
    }
}

/**
 * Check if a DEX is currently banned
 */
export async function isDexBanned(network: Network, dex: string): Promise<boolean> {
    try {
        const redis = await getRedis();
        const key = `${REDIS_KEY_PREFIX}${network}:${dex.toLowerCase()}`;
        
        const banData = await redis.get(key);
        if (banData) {
            const parsed = JSON.parse(banData);
            const ttl = await redis.ttl(key);
            console.log(`⏰ ${dex} is banned on ${network} until ${new Date(Date.now() + ttl * 1000).toISOString()}`);
            return true;
        }
        
        return false;
    } catch (error: any) {
        console.error(`Failed to check DEX ban in Redis:`, error?.message || String(error));
        return false; // Default to not banned if Redis fails
    }
}

/**
 * Handle trade/quote error and ban DEX if appropriate
 */
export async function handleDexError(network: Network, dex: string, error: any): Promise<void> {
    const errorMessage = error?.message || error?.detail || String(error);
    
    if (shouldBanDex(errorMessage)) {
        await banDex(network, dex, errorMessage.substring(0, 100));
    }
}

/**
 * Unban a DEX manually (for testing or emergency use)
 */
export async function unbanDex(network: Network, dex: string): Promise<void> {
    try {
        const redis = await getRedis();
        const key = `${REDIS_KEY_PREFIX}${network}:${dex.toLowerCase()}`;
        await redis.del(key);
        console.log(`✅ Unbanned ${dex} on ${network}`);
    } catch (error: any) {
        console.error(`Failed to unban DEX in Redis:`, error?.message || String(error));
    }
}

/**
 * Get all currently banned DEXs
 */
export async function getBannedDexs(): Promise<Array<{network: string, dex: string, reason: string, expiresAt: string}>> {
    try {
        const redis = await getRedis();
        const keys = await redis.keys(`${REDIS_KEY_PREFIX}*`);
        
        const banned = await Promise.all(
            keys.map(async (key: string) => {
                const data = await redis.get(key);
                const ttl = await redis.ttl(key);
                if (data) {
                    const parsed = JSON.parse(data);
                    const parts = key.replace(REDIS_KEY_PREFIX, '').split(':');
                    return {
                        network: parts[0],
                        dex: parts[1],
                        reason: parsed.reason,
                        expiresAt: new Date(Date.now() + ttl * 1000).toISOString()
                    };
                }
                return null;
            })
        );
        
        return banned.filter((b: any) => b !== null) as Array<{network: string, dex: string, reason: string, expiresAt: string}>;
    } catch (error: any) {
        console.error(`Failed to get banned DEXs:`, error?.message || String(error));
        return [];
    }
}
