import { Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { Request, Response } from "express";
import { ethers } from "ethers";
import { walletv2 } from "../walletv2";
import { calculateApiFeeInWei } from "../apiPricing";
import { createRetryProviderWithFailover } from "../utils/RetryProvider";
import { getAllRpcProviders } from "../rpc";

const cexRouter = Router();
const DAO_GAS = process.env.DAO_GAS as string;

/**
 * Helper to create provider with failover support
 */
function createProviderWithFailover(network: Network): ethers.providers.Provider {
    const providerUrls = getAllRpcProviders(network);
    return createRetryProviderWithFailover(providerUrls);
}

/**
 * Get native token symbol for network
 */
function getGasToken(network: Network): string {
    if (network === Network.POLYGON) return 'POL';
    return 'ETH';
}

/**
 * Send payment transaction
 */
async function sendPayment(
    wallet: ethers.Wallet,
    toAddress: string,
    amount: ethers.BigNumber,
    network: Network
): Promise<ethers.providers.TransactionResponse> {
    const provider = wallet.provider;
    if (!provider) throw new Error('Wallet has no provider');
    
    // Get current gas prices
    const feeData = await provider.getFeeData();
    
    // Estimate gas for the transfer
    const gasLimit = await provider.estimateGas({
        to: toAddress,
        value: amount,
        from: wallet.address
    });
    
    // Send transaction
    const tx = await wallet.sendTransaction({
        to: toAddress,
        value: amount,
        gasLimit: gasLimit.mul(120).div(100), // 20% buffer
        maxFeePerGas: feeData.maxFeePerGas || undefined,
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas || undefined
    });
    
    return tx;
}

/**
 * POST /api/cex/chargeFee
 * 
 * Charge CEX trading fee from gas wallet on specified network
 * 
 * Required params:
 * - apiKey: Gas wallet API key
 * - network: Network to charge from (ethereum, polygon, optimism, arbitrum, base)
 * - action: Action type (default: 'cex_trade')
 * 
 * Optional params:
 * - pair: Trading pair (for logging)
 * - exchangeOrderId: Exchange order ID (for logging)
 */
cexRouter.post("/api/cex/chargeFee", async (req: Request, res: Response) => {
    try {
        const { apiKey, network, action = 'cex_trade', pair, exchangeOrderId } = req.body;
        
        // Validate required parameters
        if (!apiKey) {
            return res.status(400).json({
                status: "fail",
                status_code: 400,
                message: "Missing required parameter: apiKey"
            });
        }
        
        if (!network) {
            return res.status(400).json({
                status: "fail",
                status_code: 400,
                message: "Missing required parameter: network"
            });
        }
        
        // Validate network
        const validNetworks = ['ethereum', 'polygon', 'optimism', 'arbitrum', 'base'];
        if (!validNetworks.includes(network.toLowerCase())) {
            return res.status(400).json({
                status: "fail",
                status_code: 400,
                message: `Invalid network. Must be one of: ${validNetworks.join(', ')}`
            });
        }
        
        const networkEnum = network.toLowerCase() as Network;
        
        console.log(`[CEX Fee] Charging fee for ${action} on ${network} (pair: ${pair || 'N/A'}, order: ${exchangeOrderId || 'N/A'})`);
        
        // Get wallet
        const wallet = await walletv2(networkEnum, apiKey, null, null);
        const provider = createProviderWithFailover(networkEnum);
        const walletWithProvider = wallet.connect(provider);
        
        // Calculate fee
        const feeWei = await calculateApiFeeInWei(action, networkEnum);
        
        if (!feeWei || feeWei.isZero()) {
            console.log(`[CEX Fee] Action '${action}' is FREE - no fee charged`);
            return res.status(200).json({
                status: "success",
                status_code: 200,
                message: `No fee required for action: ${action}`,
                fee_usd: 0,
                fee_charged: "0",
                network: network
            });
        }
        
        const feeInEther = ethers.utils.formatUnits(feeWei, 18);
        const gasToken = getGasToken(networkEnum);
        
        console.log(`[CEX Fee] Fee: ${feeInEther} ${gasToken}`);
        
        // Check balance
        const balance = await walletWithProvider.getBalance();
        const balanceInEther = ethers.utils.formatEther(balance);
        
        console.log(`[CEX Fee] Wallet Balance: ${balanceInEther} ${gasToken}`);
        
        if (balance.lt(feeWei)) {
            return res.status(402).json({
                status: "fail",
                status_code: 402,
                message: `Insufficient balance for fee payment`,
                balance: balanceInEther,
                fee_required: feeInEther,
                network: network,
                token: gasToken
            });
        }
        
        // Send payment to DAO
        const tx = await sendPayment(walletWithProvider, DAO_GAS, feeWei, networkEnum);
        
        console.log(`[CEX Fee] Payment transaction sent: ${tx.hash}`);
        
        // Wait for confirmation
        const receipt = await tx.wait(1);
        
        if (receipt.status !== 1) {
            throw new Error('Payment transaction failed');
        }
        
        console.log(`[CEX Fee] Payment confirmed: ${receipt.transactionHash}`);
        
        return res.status(200).json({
            status: "success",
            status_code: 200,
            message: "CEX trading fee charged successfully",
            fee_charged: feeInEther,
            fee_token: gasToken,
            network: network,
            transaction_hash: receipt.transactionHash,
            block_number: receipt.blockNumber,
            gas_used: receipt.gasUsed.toString()
        });
        
    } catch (error) {
        console.error('[CEX Fee] Error charging fee:', error);
        const errorMessage = error instanceof Error ? error.message : String(error);
        
        return res.status(500).json({
            status: "fail",
            status_code: 500,
            message: "Failed to charge CEX trading fee",
            error: errorMessage
        });
    }
});

/**
 * GET /api/cex/calculateFee
 * 
 * Calculate CEX trading fee without charging
 * 
 * Required params:
 * - network: Network to calculate fee for
 * - action: Action type (default: 'cex_trade')
 */
cexRouter.get("/api/cex/calculateFee", async (req: Request, res: Response) => {
    try {
        const { network, action = 'cex_trade' } = req.query;
        
        if (!network) {
            return res.status(400).json({
                status: "fail",
                status_code: 400,
                message: "Missing required parameter: network"
            });
        }
        
        const networkEnum = network as Network;
        const feeWei = await calculateApiFeeInWei(action as string, networkEnum);
        
        if (!feeWei) {
            return res.status(500).json({
                status: "fail",
                status_code: 500,
                message: "Unable to calculate fee (price data unavailable)"
            });
        }
        
        const feeInEther = ethers.utils.formatUnits(feeWei, 18);
        const gasToken = getGasToken(networkEnum);
        
        return res.status(200).json({
            status: "success",
            status_code: 200,
            fee: feeInEther,
            token: gasToken,
            network: network,
            action: action
        });
        
    } catch (error) {
        console.error('[CEX Fee] Error calculating fee:', error);
        const errorMessage = error instanceof Error ? error.message : String(error);
        
        return res.status(500).json({
            status: "fail",
            status_code: 500,
            message: "Failed to calculate fee",
            error: errorMessage
        });
    }
});

export default cexRouter;
