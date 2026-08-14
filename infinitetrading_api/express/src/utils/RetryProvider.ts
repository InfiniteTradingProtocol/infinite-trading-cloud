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
    // One JsonRpcProvider instance per URL — avoids any need to mutate
    // connection.url (which is non-configurable in some ethers.js builds)
    private fallbackProviders: ethers.providers.JsonRpcProvider[];
    private drpcSkipUntil: number = 0;

    constructor(
        url: string | string[],
        network?: ethers.providers.Networkish,
        maxRetries: number = 3,
        retryDelay: number = 1000
    ) {
        const urls = Array.isArray(url) ? url : [url];
        super(urls[0], network);

        this.maxRetries = maxRetries;
        this.retryDelay = retryDelay;
        this.fallbackUrls = urls;
        // Pre-create one provider per URL so send() routes via the correct connection
        this.fallbackProviders = urls.map(u => new ethers.providers.JsonRpcProvider(u, network));

        if (urls.length > 1) {
            console.log(`[RetryProvider] Initialized with ${urls.length} providers for failover`);
        }
    }

    private isRetryableError(error: any, method: string): { retryable: boolean; reason: string } {
        // Check for specific non-retryable error messages FIRST, before the
        // generic SERVER_ERROR check — Alchemy wraps EVM reverts as SERVER_ERROR,
        // so we must detect the actual revert reason before falling through.
        const errorMessage = (error?.message || error?.body || '').toLowerCase();
        const errorData = error?.error?.message?.toLowerCase() || '';
        const errorCode = error?.code || '';
        const combinedError = errorMessage + ' ' + errorData;

        // True EVM reverts — not retryable regardless of HTTP status code
        if (combinedError.includes('execution reverted') ||
            combinedError.includes('transaction reverted')) {
            return { retryable: false, reason: 'transaction_reverted' };
        }

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

        // Server errors (500, 502, 503, 504) are retryable only after
        // filtering known non-retryable conditions above.
        const isServerError = error?.code === 'SERVER_ERROR' ||
            [500, 502, 503, 504].includes(error?.status);

        if (isServerError) {
            return { retryable: true, reason: 'server_error' };
        }

        // Slippage exceeded - price moved too much
        if (combinedError.includes('slippage') ||
            combinedError.includes('price impact') ||
            combinedError.includes('too little received') ||
            combinedError.includes('excessive slippage')) {
            return { retryable: false, reason: 'slippage_exceeded' };
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

        // Rate limiting is retryable and can be handled by higher-level caller logic.
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
            // Skip dRPC if recently rate-limited/server error
            const url = this.fallbackUrls[providerIndex];
            if (url.includes('drpc') && Date.now() < this.drpcSkipUntil) {
                console.warn(`[Provider Failover] Skipping dRPC due to recent rate limit/server error.`);
                continue;
            }
            // Retry on current provider
            for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
                totalAttempts++;
                try {
                    // Route to the provider for this index — avoids mutating connection.url
                    return await this.fallbackProviders[providerIndex].send(method, params);
                } catch (error: any) {
                    lastError = error;
                    // Check if error is retryable
                    const { retryable, reason } = this.isRetryableError(error, method);
                    const isLastAttemptOnProvider = attempt === this.maxRetries;
                    const isLastProvider = providerIndex === this.fallbackUrls.length - 1;
                    const providerName = url.includes('drpc') ? 'dRPC' : url.includes('alchemy') ? 'Alchemy' : url.includes('infura') ? 'Infura' : 'Unknown';

                    // If error is not retryable, fail immediately
                    if (!retryable) {
                        console.error(`[RPC Non-Retryable] ${method} failed with ${reason} on ${providerName}`);
                        console.error(`[RPC Non-Retryable] Error: ${error?.message || 'unknown'}`);
                        // If dRPC and rate limit/server error, skip for 5 minutes
                        if (providerName === 'dRPC' && (reason === 'rate_limited' || reason === 'server_error')) {
                            this.drpcSkipUntil = Date.now() + 5 * 60 * 1000;
                            console.warn(`[Provider Failover] dRPC will be skipped for 5 minutes due to ${reason}.`);
                        }
                        throw error;
                    }

                    // Error is retryable - log and retry
                    console.warn(`[RPC Retry] ${method} failed on ${providerName} (attempt ${attempt}/${this.maxRetries}) - Reason: ${reason}`);
                    // Log trace ID if available
                    if (error?.body) {
                        try {
                            const body = JSON.parse(error.body);
                            const traceId = body?.error?.message || 'unknown';
                            console.warn(`[RPC Retry] Error: ${traceId.substring(0, 100)}`);
                        } catch { }
                    }
                    // If last attempt on this provider, move to next
                    if (isLastAttemptOnProvider && !isLastProvider) {
                        console.warn(`[Provider Failover] Switching to provider ${providerIndex + 2}/${this.fallbackUrls.length}`);
                        const nextUrl = this.fallbackUrls[providerIndex + 1];
                        console.warn(`[Provider Failover] New URL: ${nextUrl.substring(0, 50)}...`);
                        console.warn(`[RPC Retry] Retrying with next provider...`);
                        break; // Break retry loop to try next provider
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
