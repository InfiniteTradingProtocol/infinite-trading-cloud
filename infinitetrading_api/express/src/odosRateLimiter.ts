/**
 * ODOS Rate Limiter - Global axios interceptor
 * This patches axios globally to add rate limiting and retry logic for ODOS API calls
 * Import this early in your application to enable protection against 429 errors
 */

import axios from 'axios';

const odosRequestQueue = new Map<string, number[]>();
const MAX_ODOS_RPS = 2; // Max requests per second for ODOS API

/**
 * Check if we need to rate limit this request
 */
async function checkOdosRateLimit(): Promise<void> {
  const now = Date.now();
  const timestamps = odosRequestQueue.get('odos') || [];
  const validTimestamps = timestamps.filter(ts => now - ts < 1000);
  
  // Rate limit: wait if needed
  if (validTimestamps.length >= MAX_ODOS_RPS) {
    const waitTime = 1100 - (now - validTimestamps[0]); // Add 100ms buffer
    console.log(`[ODOS Rate Limit] Waiting ${waitTime}ms before next request...`);
    await new Promise(resolve => setTimeout(resolve, waitTime));
    return checkOdosRateLimit(); // Check again
  }
  
  validTimestamps.push(now);
  odosRequestQueue.set('odos', validTimestamps);
}

/**
 * Sleep helper
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Install axios interceptor for ODOS rate limiting
 */
export function installOdosRateLimiter() {
  // Request interceptor - add rate limiting before request
  axios.interceptors.request.use(
    async (config) => {
      const url = config.url || '';
      
      // Check if this is an ODOS API call
      if (url.includes('odos.xyz') || url.includes('enterprise-api.odos')) {
        await checkOdosRateLimit();
        console.log(`[ODOS] Making request to ${url.includes('quote') ? 'quote' : 'assemble'} endpoint`);
      }
      
      return config;
    },
    (error) => Promise.reject(error)
  );

  // Response interceptor - handle 429 errors with retry
  axios.interceptors.response.use(
    (response) => response,
    async (error) => {
      const config = error.config;
      const url = config?.url || '';
      
      // Only handle ODOS API errors
      if (!url.includes('odos.xyz') && !url.includes('enterprise-api.odos')) {
        return Promise.reject(error);
      }

      const status = error?.response?.status;
      const is429 = status === 429;
      
      // Initialize retry count
      config._retryCount = config._retryCount || 0;
      
      // Max 3 retries for 429 errors
      if (is429 && config._retryCount < 3) {
        config._retryCount++;
        const delay = config._retryCount * 1000; // 1s, 2s, 3s (linear backoff to avoid stale quotes)
        
        console.warn(`[ODOS 429] Rate limited! Retry ${config._retryCount}/3 after ${delay}ms`);
        console.warn(`[ODOS 429] Error: ${error?.response?.data?.detail || 'Too Many Requests'}`);
        
        await sleep(delay);
        
        // Retry the request
        return axios(config);
      }
      
      // Log the final error
      if (is429) {
        console.error(`[ODOS 429] Failed after 3 retries. Please upgrade your ODOS API plan or reduce request frequency.`);
      }
      
      return Promise.reject(error);
    }
  );

  console.log('✅ ODOS rate limiter installed (2 RPS with retry logic)');
}

// Auto-install when module is imported
installOdosRateLimiter();

export default {
  installOdosRateLimiter
};
