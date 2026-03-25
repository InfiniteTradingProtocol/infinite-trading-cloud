import { Network } from "@dhedge/v2-sdk";
import { createClient } from "redis";
import { ethers } from "ethers";

// Connect to Redis
const redisClient = createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
redisClient.on('error', (err) => console.error('Redis Client Error', err));

// Initialize Redis connection
let redisConnected = false;
(async () => {
  try {
    await redisClient.connect();
    redisConnected = true;
    console.log('Redis connected for API pricing');
  } catch (err) {
    console.error('Failed to connect to Redis:', err);
  }
})();

// API Action Pricing in USD
export const API_PRICING_USD: Record<string, number> = {
  // Trading Actions
  'trade': 0.10,           // Standard trade execution - 10 cents
  'approve': 0.02,         // Token approval - 2 cents
  'swap': 0.10,            // Direct swap - 10 cents
  
  // CEX Trading Actions
  'cex_trade': 0.10,       // CEX trade execution - 10 cents
  
  // Pool Actions  
  'deposit': 0.00,         // Pool deposit - FREE
  'withdraw': 0.00,        // Pool withdrawal - FREE
  'poolComposition': 0.00, // Get pool composition - FREE
  
  // Lending Actions
  'lend': 0.05,            // Lending operation - 5 cents
  'borrow': 0.05,          // Borrow operation - 5 cents
  'repay': 0.05,           // Repay loan - 5 cents
  'claimRewards': 0.00,    // Claim rewards - FREE
  
  // Administrative
  'estimate': 0.00,        // Gas estimation - FREE
  'query': 0.00,           // General query - FREE
  
  // Default fallback
  'default': 0.00          // FREE by default
};

/**
 * Get ETH price from Redis
 * @returns ETH price in USD, or null if unavailable
 */
export async function getEthPriceUSD(): Promise<number | null> {
  try {
    if (!redisConnected) {
      console.warn('Redis not connected, cannot fetch ETH price');
      return null;
    }
    
    const price = await redisClient.get('coinbase_ETH-USD');
    if (!price) {
      console.warn('ETH price not found in Redis');
      return null;
    }
    
    const ethPrice = parseFloat(price);
    console.log(`ETH Price from Redis: $${ethPrice}`);
    return ethPrice;
  } catch (error) {
    console.error('Error fetching ETH price from Redis:', error);
    return null;
  }
}

/**
 * Get the price for a specific network's native token
 * For most networks this is ETH, but Polygon uses MATIC
 */
export async function getNativeTokenPriceUSD(network: Network): Promise<number | null> {
  try {
    if (!redisConnected) return null;
    
    let redisKey: string;
    
    switch (network) {
      case Network.POLYGON:
        redisKey = 'coinbase_POL-USD'; // Polygon uses MATIC (now POL)
        break;
      default:
        redisKey = 'coinbase_ETH-USD'; // Most networks use ETH
    }
    
    const price = await redisClient.get(redisKey);
    if (!price) {
      console.warn(`${network} price not found in Redis (key: ${redisKey})`);
      return null;
    }
    
    return parseFloat(price);
  } catch (error) {
    console.error(`Error fetching ${network} price:`, error);
    return null;
  }
}

/**
 * Calculate API fee in native token (ETH/MATIC) based on USD price
 * @param action - The API action being performed
 * @param network - The blockchain network
 * @returns Fee amount in ETH/MATIC as string, or null if price unavailable
 */
export async function calculateApiFeeInNativeToken(
  action: string,
  network: Network
): Promise<string | null> {
  try {
    // Get USD price for this action
    const usdPrice = API_PRICING_USD[action] || API_PRICING_USD['default'];
    console.log(`Action: ${action}, USD Price: $${usdPrice}`);
    
    // Get native token price
    const tokenPrice = await getNativeTokenPriceUSD(network);
    if (!tokenPrice) {
      console.warn('Token price unavailable, cannot calculate fee');
      return null;
    }
    
    // Calculate fee in native token
    const feeInToken = usdPrice / tokenPrice;
    const feeString = feeInToken.toFixed(18); // Use 18 decimals for precision
    
    console.log(`Fee Calculation: $${usdPrice} / $${tokenPrice} = ${feeInToken} native token`);
    
    return feeString;
  } catch (error) {
    console.error('Error calculating API fee:', error);
    return null;
  }
}

/**
 * Calculate API fee in wei/smallest unit
 * @param action - The API action being performed
 * @param network - The blockchain network
 * @returns Fee amount as BigNumber in wei, or null if price unavailable
 */
export async function calculateApiFeeInWei(
  action: string,
  network: Network
): Promise<ethers.BigNumber | null> {
  try {
    const feeString = await calculateApiFeeInNativeToken(action, network);
    if (!feeString) return null;
    
    // Convert to wei
    const feeWei = ethers.utils.parseEther(feeString);
    console.log(`Fee in wei: ${feeWei.toString()}`);
    
    return feeWei;
  } catch (error) {
    console.error('Error calculating fee in wei:', error);
    return null;
  }
}

/**
 * Get the pricing for a specific action in USD
 */
export function getActionPriceUSD(action: string): number {
  return API_PRICING_USD[action] || API_PRICING_USD['default'];
}

/**
 * List all available actions and their prices
 */
export function getAllPricing(): Record<string, number> {
  return { ...API_PRICING_USD };
}

/**
 * Update pricing for a specific action (for testing or admin changes)
 */
export function updateActionPrice(action: string, priceUSD: number): void {
  API_PRICING_USD[action] = priceUSD;
  console.log(`Updated pricing for ${action}: $${priceUSD}`);
}

export default {
  getEthPriceUSD,
  getNativeTokenPriceUSD,
  calculateApiFeeInNativeToken,
  calculateApiFeeInWei,
  getActionPriceUSD,
  getAllPricing,
  updateActionPrice,
  API_PRICING_USD
};
