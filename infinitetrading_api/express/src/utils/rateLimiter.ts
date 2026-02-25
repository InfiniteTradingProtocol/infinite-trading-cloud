import { Network } from "@dhedge/v2-sdk";

/**
 * Simple in-memory rate limiter for ODOS API calls
 * Tracks requests per network to avoid hitting rate limits
 */
class RateLimiter {
  private requestTimestamps: Map<string, number[]> = new Map();
  private readonly maxRequestsPerSecond: number;
  private readonly windowMs: number = 1000; // 1 second window

  constructor(maxRequestsPerSecond: number = 2) {
    this.maxRequestsPerSecond = maxRequestsPerSecond;
  }

  /**
   * Check if we can make a request for this network
   * If not, wait until we can
   */
  async waitForSlot(network: Network): Promise<void> {
    const key = `odos_${network}`;
    const now = Date.now();
    
    // Clean up old timestamps
    const timestamps = this.requestTimestamps.get(key) || [];
    const validTimestamps = timestamps.filter(ts => now - ts < this.windowMs);
    
    // If we're at the limit, wait
    if (validTimestamps.length >= this.maxRequestsPerSecond) {
      const oldestTimestamp = validTimestamps[0];
      const waitTime = this.windowMs - (now - oldestTimestamp) + 100; // Add 100ms buffer
      
      console.log(`Rate limit: waiting ${waitTime}ms for ${network}`);
      await this.sleep(waitTime);
      
      // Retry after waiting
      return this.waitForSlot(network);
    }
    
    // Record this request
    validTimestamps.push(now);
    this.requestTimestamps.set(key, validTimestamps);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Reset rate limiter (useful for testing)
   */
  reset(): void {
    this.requestTimestamps.clear();
  }
}

/**
 * Retry function with exponential backoff
 * Handles 429 errors and other transient failures
 */
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  options: {
    maxRetries?: number;
    initialDelayMs?: number;
    maxDelayMs?: number;
    backoffMultiplier?: number;
    retryOn429?: boolean;
  } = {}
): Promise<T> {
  const {
    maxRetries = 3,
    initialDelayMs = 1000,
    maxDelayMs = 10000,
    backoffMultiplier = 2,
    retryOn429 = true
  } = options;

  let lastError: any;
  let delayMs = initialDelayMs;

  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error: any) {
      lastError = error;
      
      // Check if it's a rate limit error
      const is429 = error?.response?.status === 429 || 
                    error?.message?.includes('429') ||
                    error?.message?.includes('Too Many Requests');
      
      // Check if it's retryable
      const isRetryable = is429 || 
                         error?.code === 'ECONNRESET' ||
                         error?.code === 'ETIMEDOUT' ||
                         error?.response?.status >= 500;
      
      // Don't retry if we've exhausted attempts or error is not retryable
      if (attempt >= maxRetries || !isRetryable) {
        console.error(`Request failed after ${attempt + 1} attempts:`, error?.message || error);
        throw error;
      }

      // For 429, use longer delays
      if (is429 && retryOn429) {
        delayMs = Math.min(delayMs * 2, maxDelayMs);
        console.warn(`Rate limited (429), retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries})`);
      } else {
        console.warn(`Request failed, retrying in ${delayMs}ms (attempt ${attempt + 1}/${maxRetries})`);
      }

      await new Promise(resolve => setTimeout(resolve, delayMs));
      
      // Exponential backoff for next attempt
      delayMs = Math.min(delayMs * backoffMultiplier, maxDelayMs);
    }
  }

  throw lastError;
}

// Export singleton instance
export const odosRateLimiter = new RateLimiter(2); // 2 requests per second

/**
 * Wrap an ODOS API call with rate limiting and retry logic
 */
export async function withOdosRateLimit<T>(
  network: Network,
  fn: () => Promise<T>,
  retryOptions?: Parameters<typeof retryWithBackoff>[1]
): Promise<T> {
  // Wait for rate limiter
  await odosRateLimiter.waitForSlot(network);
  
  // Execute with retry logic
  return retryWithBackoff(fn, {
    maxRetries: 3,
    initialDelayMs: 2000,
    maxDelayMs: 10000,
    backoffMultiplier: 2,
    retryOn429: true,
    ...retryOptions
  });
}

export default {
  odosRateLimiter,
  retryWithBackoff,
  withOdosRateLimit
};
