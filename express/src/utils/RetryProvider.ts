/**
 * RetryProvider - Custom JsonRpcProvider with automatic retry logic and provider failover
 * Wraps ethers.js JsonRpcProvider to handle RPC provider failures gracefully
 * Features:
 * - Automatic retries on 500 errors (3 attempts per provider)
 * - Automatic failover to alternative providers (dRPC -> Alchemy -> Infura)
 * - Comprehensive logging for monitoring
 */

import { ethers } from "@dhedge/v2-sdk";

export class RetryProvider extends ethers.providers.JsonRpcProvider {
    private maxRetries: number;
    private retryDelay: number;
    private fallbackUrls: string[];
    private currentProviderIndex: number = 0;

    constructor(
        url: string | string[], 
        network?: ethers.providers.Networkish, 
        maxRetries: number = 3, 
        retryDelay: number = 1000
    ) {
        // If array provided, use first URL as primary
        const primaryUrl = Array.isArray(url) ? url[0] : url;
        super(primaryUrl, network);
        
        this.maxRetries = maxRetries;
        this.retryDelay = retryDelay;
        this.fallbackUrls = Array.isArray(url) ? url : [url];
        
        if (this.fallbackUrls.length > 1) {
            console.log(`[RetryProvider] Initialized with ${this.fallbackUrls.length} providers for failover`);
        }
    }

    /**
     * Switch to next provider in fallback list
     */
    private switchProvider(): boolean {
        if (this.currentProviderIndex < this.fallbackUrls.length - 1) {
            this.currentProviderIndex++;
            const newUrl = this.fallbackUrls[this.currentProviderIndex];
            
            // Update connection URL
            (this.connection as any).url = newUrl;
            
            console.warn(`[Provider Failover] Switching to provider ${this.currentProviderIndex + 1}/${this.fallbackUrls.length}`);
            console.warn(`[Provider Failover] New URL: ${newUrl.substring(0, 50)}...`);
            
            return true;
        }
        return false;
    }

    /**
     * Check if error is retryable (temporary/infrastructure) or permanent (business logic)
     */
    private isRetryableError(error: any, method: string): { retryable: boolean; reason: string } {
        // Server errors (500, 502, 503, 504) are retryable
        const isServerError = error?.code === 'SERVER_ERROR' || 
                            [500, 502, 503, 504].includes(error?.status);
        
        if (isServerError) {
            return { retryable: true, reason: 'server_error' };
        }

        // Check for specific non-retryable error messages
        const errorMessage = (error?.message || error?.body || '').toLowerCase();
        const errorData = error?.error?.message?.toLowerCase() || '';
        const errorCode = error?.code || '';
        const combinedError = errorMessage + ' ' + errorData;

        // CALL_EXCEPTION usually means transaction will revert - not retryable
        if (errorCode === 'CALL_EXCEPTION' || combinedError.includes('call_exception')) {
            return { retryable: false, reason: 'call_exception' };
        }

        // Transaction failed/reverted - check if it's a receipt status issue
        if (combinedError.includes('transaction failed') || 
            combinedError.includes('status\":0') ||
            combinedError.includes('status: 0')) {
            return { retryable: false, reason: 'transaction_failed' };
        }

        // Insufficient allowance - user needs to approve more tokens
        if (combinedError.includes('insufficient allowance') || 
            combinedError.includes('erc20: transfer amount exceeds allowance') ||
            combinedError.includes('transfer amount exceeds allowance')) {
            return { retryable: false, reason: 'insufficient_allowance' };
        }

        // Insufficient balance - user doesn't have enough tokens
        if (combinedError.includes('insufficient funds') ||
            combinedError.includes('insufficient balance') ||
            combinedError.includes('transfer amount exceeds balance')) {
            return { retryable: false, reason: 'insufficient_balance' };
        }

        // Slippage exceeded - price moved too much
        if (combinedError.includes('slippage') ||
            combinedError.includes('price impact') ||
            combinedError.includes('too little received') ||
            combinedError.includes('excessive slippage')) {
            return { retryable: false, reason: 'slippage_exceeded' };
        }

        // Transaction reverted with reason
        if (combinedError.includes('execution reverted') ||
            combinedError.includes('transaction reverted')) {
            return { retryable: false, reason: 'transaction_reverted' };
        }

        // Gas estimation failures (usually indicate transaction will fail)
        if (method === 'eth_estimateGas' && error?.code === -32000) {
            return { retryable: false, reason: 'gas_estimation_failed' };
        }

        // Nonce too low (transaction already mined or replaced)
        if (combinedError.includes('nonce too low') ||
            combinedError.includes('already known') ||
            combinedError.includes('replacement transaction underpriced')) {
            return { retryable: false, reason: 'nonce_issue' };
        }

        // Invalid parameters
        if (combinedError.includes('invalid argument') ||
            combinedError.includes('invalid address') ||
            combinedError.includes('invalid parameters')) {
            return { retryable: false, reason: 'invalid_parameters' };
        }

        // Network/timeout errors are retryable
        if (error?.code === 'TIMEOUT' || 
            error?.code === 'NETWORK_ERROR' ||
            combinedError.includes('timeout') ||
            combinedError.includes('network')) {
            return { retryable: true, reason: 'network_timeout' };
        }

        // Rate limiting is retryable (handled separately by ODOS rate limiter)
        if (error?.status === 429 || combinedError.includes('rate limit')) {
            return { retryable: true, reason: 'rate_limited' };
        }

        // Default: if we're not sure, don't retry to avoid wasting calls
        return { retryable: false, reason: 'unknown_error' };
    }

    /**
     * Override send method to add retry logic and provider failover
     */
    async send(method: string, params: Array<any>): Promise<any> {
        let lastError: any;
        let totalAttempts = 0;
        const maxTotalAttempts = this.maxRetries * this.fallbackUrls.length;

        // Try each provider with retries
        for (let providerIndex = 0; providerIndex < this.fallbackUrls.length; providerIndex++) {
            // Retry on current provider
            for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
                totalAttempts++;
                
                try {
                    return await super.send(method, params);
                } catch (error: any) {
                    lastError = error;
                    
                    // Check if error is retryable
                    const { retryable, reason } = this.isRetryableError(error, method);
                    const isLastAttemptOnProvider = attempt === this.maxRetries;
                    const isLastProvider = providerIndex === this.fallbackUrls.length - 1;

                    // If error is not retryable, fail immediately
                    if (!retryable) {
                        const providerName = this.fallbackUrls[this.currentProviderIndex].includes('drpc') ? 'dRPC' :
                                           this.fallbackUrls[this.currentProviderIndex].includes('alchemy') ? 'Alchemy' :
                                           this.fallbackUrls[this.currentProviderIndex].includes('infura') ? 'Infura' : 'Unknown';
                        
                        console.error(`[RPC Non-Retryable] ${method} failed with ${reason} on ${providerName}`);
                        console.error(`[RPC Non-Retryable] Error: ${error?.message || 'unknown'}`);
                        throw error;
                    }

                    // Error is retryable - log and retry
                    const providerName = this.fallbackUrls[this.currentProviderIndex].includes('drpc') ? 'dRPC' :
                                       this.fallbackUrls[this.currentProviderIndex].includes('alchemy') ? 'Alchemy' :
                                       this.fallbackUrls[this.currentProviderIndex].includes('infura') ? 'Infura' : 'Unknown';
                    
                    console.warn(`[RPC Retry] ${method} failed on ${providerName} (attempt ${attempt}/${this.maxRetries}) - Reason: ${reason}`);
                    
                    // Log trace ID if available
                    if (error?.body) {
                        try {
                            const body = JSON.parse(error.body);
                            const traceId = body?.error?.message || 'unknown';
                            console.warn(`[RPC Retry] Error: ${traceId.substring(0, 100)}`);
                        } catch {}
                    }

                    // If last attempt on this provider, try switching
                    if (isLastAttemptOnProvider && !isLastProvider) {
                        if (this.switchProvider()) {
                            console.warn(`[RPC Retry] Retrying with next provider...`);
                            break; // Break retry loop to try next provider
                        }
                    } else if (!isLastAttemptOnProvider) {
                        // Retry on same provider with delay
                        const delay = attempt * this.retryDelay;
                        console.warn(`[RPC Retry] Retrying in ${delay}ms...`);
                        await this.sleep(delay);
                    }
                }
            }
        }

        console.error(`[RPC Error] ${method} failed after ${totalAttempts} attempts across ${this.fallbackUrls.length} provider(s)`);
        throw lastError;
    }

    private sleep(ms: number): Promise<void> {
        return new Promise(resolve => setTimeout(resolve, ms));
    }
}

/**
 * Factory function to create RetryProvider instances with single URL
 */
export function createRetryProvider(url: string, network?: ethers.providers.Networkish): RetryProvider {
    return new RetryProvider(url, network, 3, 1000);
}

/**
 * Factory function to create RetryProvider with multiple fallback URLs
 */
export function createRetryProviderWithFailover(urls: string[], network?: ethers.providers.Networkish): RetryProvider {
    return new RetryProvider(urls, network, 3, 1000);
}
