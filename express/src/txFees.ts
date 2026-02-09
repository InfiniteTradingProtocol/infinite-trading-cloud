import { ethers, Network } from "@dhedge/v2-sdk";
import { rpc } from "./rpc";
import { walletv2,getProvider } from './walletv2'
import * as path from 'path';
import axios from "axios";
import { calculateApiFeeInWei } from "./apiPricing";
//import { BigNumber } from "bignumber.js"
import type { BigNumber as EthersBN } from "ethers";
require("dotenv").config({ path: '../.env' });

const DAO_GAS = process.env.DAO_GAS as string;
const MASTER_APIKEY = process.env.MASTER_APIKEY as string;

//const GAS_MULTIPLIER = 10;
type GasLike =
  | string
  | number
  | bigint
  | EthersBN
  | { gas: string | number | bigint | EthersBN }
  | null;
const GAS_MULTIPLIERS: Record<string, number> = {
    optimism: 20,
    base: 5,
    polygon: 15,
    arbitrum: 5,
    ethereum:2,
    default: 10, // fallback if network not listed
};
const INFURA_API_KEY = process.env.INFURA_PROJECT_ID as string;

function getGasToken(network: Network) {
        if (network == "polygon") return 'MATIC'
        return 'ETH'
}
const networkChainIdMap: { [key in Network]: number } = {
    [Network.ETHEREUM]: 1,
    [Network.POLYGON]: 137,
    [Network.OPTIMISM]: 10,
    [Network.ARBITRUM]: 42161,
    [Network.BASE]: 8453,
    [Network.PLASMA]: 13473, // Plasma chain ID
};

export type feeData = {
  gasLimit: string;
  maxFeePerGas: string;
  maxPriorityFeePerGas: string;
  type?: number;
}

//type getFeeData = {
//  maxFeePerGas: ethers.BigNumber;
//  maxPriorityFeePerGas: ethers.BigNumber;
//}

//async function getFeeData(network: Network,provider: string | ethers.providers.Provider | null,key: string | null): Promise<getFeeData> {
//	try {
//		let rpc_provider: ethers.providers.Provider;
//                if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
//                else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
//    		return await rpc_provider.getFeeData();
//  	} catch (error) {
//		const error_msg = "Error fetching fee data: ${error}";
//    		console.error(error_msg);
//  		throw error_msg;
//  	}
//}

async function estimateSendGas(provider: ethers.providers.Provider, toAddress: string, value: ethers.BigNumberish) {
    const gasLimit = await provider.estimateGas({ to: toAddress, value });
    return gasLimit;
}

async function getGasPrice(network: Network,provider: string | ethers.providers.Provider | null,key: string | null): Promise<string> {
	try {
		let rpc_provider: ethers.providers.Provider;
		if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
        	else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
		const gasPrice = await rpc_provider.getGasPrice();
		const gasPriceInGwei = await ethers.utils.formatUnits(gasPrice, "gwei");
		return gasPriceInGwei;
	} catch (error) {
	    const error_msg = `Error fetching gas price: ${String(error)}`;
            console.error(error_msg);
            throw new Error(error_msg);
	}
}    

function sleep(ms: number): Promise<void> { return new Promise(resolve => setTimeout(resolve, ms)); }


export const txFees = async (network: Network, provider: string | ethers.providers.Provider | null, key: string | null, estimatedGasLike: GasLike): Promise<feeData> => {
  try {
    // normalize estimated gas
	let estBN: ethers.BigNumber | null = null;

	if (estimatedGasLike != null) {
	  if (
	    typeof estimatedGasLike === "string" ||
	    typeof estimatedGasLike === "number" ||
	    typeof estimatedGasLike === "bigint"
	  ) {
	    estBN = ethers.BigNumber.from(estimatedGasLike.toString());
	  } else if (ethers.BigNumber.isBigNumber(estimatedGasLike)) {
	    estBN = estimatedGasLike as ethers.BigNumber;
	  } else if (
	    typeof estimatedGasLike === "object" &&
	    "gas" in (estimatedGasLike as any) &&
	    (estimatedGasLike as any).gas != null
	  ) {
	    const g = (estimatedGasLike as any).gas;
	    estBN = ethers.BigNumber.isBigNumber(g)
	      ? (g as ethers.BigNumber)
	      : ethers.BigNumber.from(g.toString());
	  }
	}

	const gasLimit = estBN ? estBN.mul(3).toString() : "10000000";
	if (network === Network.POLYGON) {
      		const { data } = await axios.get("https://gasstation.polygon.technology/v2");
      		const toGweiStr = (n: number) => n.toFixed(9); // rounds to 9 dp
		//const maxPriorityFeePerGas = ethers.utils
        	//.parseUnits(((data.fast.maxPriorityFee ?? 0) * 1.1).toString(), "gwei")
        	//.toString();
      		//const maxFeePerGas = ethers.utils
        	//.parseUnits(((data.fast.maxFee ?? 0) * 2).toString(), "gwei")
        	//.toString();
		const maxPriorityFeePerGas = ethers.utils
		  .parseUnits(toGweiStr((data.fast.maxPriorityFee ?? 0) * 1.1), "gwei")
		  .toString();
		const maxFeePerGas = ethers.utils
		  .parseUnits(toGweiStr((data.fast.maxFee ?? 0) * 2), "gwei")
		  .toString();
      		return { gasLimit, maxPriorityFeePerGas, maxFeePerGas, type: 2 as const };
    	} else {
     		 const chainId = networkChainIdMap[network];
      		const { data } = await axios.get(
        	`https://gas.api.infura.io/v3/${INFURA_API_KEY}/networks/${chainId}/suggestedGasFees`
      	);
      	const maxPriorityFeePerGas = ethers.utils
        .parseUnits(String(data.high.suggestedMaxPriorityFeePerGas), "gwei")
        .toString();
      	const maxFeePerGas = ethers.utils
        .parseUnits(String(data.high.suggestedMaxFeePerGas), "gwei")
        .toString();
      	return { gasLimit, maxPriorityFeePerGas, maxFeePerGas, type: 2 as const };
    	}
  } catch (err) {
    console.error("txFees error:", err);
    throw (err instanceof Error ? err : new Error(String(err)));
  }
}

// Start with your parameters
//gas_limit = 420000
//base_fee_per_gas = 0.05 gwei
//priority_fee_per_gas = 0.1 gwei
 
// Max fee per gas is the sum of the base fee and the priority fee
//max_fee_per_gas = base_fee_per_gas + priority_fee_per_gas = 0.15 gwei
 
// Execution gas fee is the product of the gas limit and the max fee per gas
//execution_gas_fee = gas_limit * max_fee_per_gas = 420000 * 0.15 gwei = 0.000063 ETH

async function sendTransaction(
  network: Network,
  apiKey: string,
  toAddress: string,
  value: string,  // ETH-denominated decimal string
  provider: string | ethers.providers.Provider | null,
  key: string | null,
  ethers_wallet: ethers.Wallet | null,
  balance: ethers.BigNumber | null
) {
  const isProviderLike = (p: any): p is ethers.providers.Provider =>
    !!p && typeof p.getNetwork === "function";

  const assertEthDecimal = (s: string) => {
    if (!/^(0|[1-9]\d*)(\.\d{1,18})?$/.test(s)) { throw new Error(`Invalid ETH decimal string (no scientific notation, max 18 dp): "${s}"`); }
  };

  try {
    console.log("Entering sendTransaction function");

    let wallet: ethers.Wallet;
    if (ethers_wallet == null) wallet = await walletv2(network, apiKey, provider, key);
    else wallet = ethers_wallet;

    let rpc_provider: ethers.providers.Provider;
    if (isProviderLike(provider)) rpc_provider = provider;
    else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));

    // 1) Validate & parse value (ETH string -> wei BigNumber)
    assertEthDecimal(value);
    const parsedValue = ethers.utils.parseEther(value); // don't .toString()

    // 2) Gas params
    const gasLimit = ethers.BigNumber.from(500_000); // consider dialing this down if possible
    if (balance == null) balance = await rpc_provider.getBalance(wallet.address);

    const feeData = await txFees(network, rpc_provider, key, gasLimit.toString());
    const maxPriorityFeePerGas = ethers.BigNumber.from(feeData.maxPriorityFeePerGas);
    const maxFeePerGas = ethers.BigNumber.from(feeData.maxFeePerGas);

    // 3) Total cost check (wei math)
    const totalGasCost = gasLimit.mul(maxFeePerGas);
    const totalCost = parsedValue.add(totalGasCost);

    const gasToken = getGasToken(network);
    console.log("Sending payment transaction");
    console.log(
      `Address: ${wallet.address} Network: ${network} ` +
      `Balance: ${ethers.utils.formatEther(balance)} ${gasToken} ` +
      `Payment amount: ${ethers.utils.formatUnits(parsedValue, 18)} ${gasToken}`
    );
    console.log(`Total Cost: ${ethers.utils.formatUnits(totalCost, 18)} ${gasToken}`);

    if (balance.lt(totalCost)) {
      throw new Error("Insufficient funds for API Payment and Transaction cost");
    }

    // 4) Build tx (reuse parsedValue, don’t re-parse)
    const tx: ethers.providers.TransactionRequest = {
      to: toAddress,
      value: parsedValue,
      gasLimit,
      maxPriorityFeePerGas,
      maxFeePerGas,
      type: 2, // EIP-1559
    };

    const sentTx = await wallet.sendTransaction(tx);
    console.log("API Payment sent:", sentTx.hash);
    return sentTx;
  } catch (err) {
    console.error("sendTransaction error:", err);
    throw err;
  }
}

async function waitForReceiptWithTimeout(tx: any, timeout: number, provider: ethers.providers.Provider) {
    if (typeof tx === "string") {
        // If tx is a hash, wait for the receipt using the provider
        return Promise.race([
            provider.waitForTransaction(tx, 1, timeout).catch(() => {
                throw new Error("Transaction receipt timeout");
            }),
        ]);
    } else if (typeof tx.wait === "function") {
        // If tx is a transaction response, use tx.wait
        return Promise.race([
            tx.wait(),
            new Promise((_, reject) => setTimeout(() => reject(new Error("Transaction receipt timeout")), timeout)),
        ]);
    } else {
        throw new Error("Invalid transaction object");
    }
}


export async function apiPayment(network: Network, apiKey: string, tx: any, provider: string | ethers.providers.Provider | null, key: string | null,ethers_wallet: ethers.Wallet | null) {
    try {
	console.log("Entering apiPayment function")
	let wallet: ethers.Wallet;
    	if (ethers_wallet == null) wallet = await walletv2(network,apiKey,provider,key)
    	else wallet = ethers_wallet
        //if (apiKey == MASTER_APIKEY) { return "Master API Key, No API Payment" }
	//console.log(tx);
	let rpc_provider: ethers.providers.Provider;
        if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
        else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
	const receipt = await waitForReceiptWithTimeout(tx, 20000,rpc_provider).catch(error => { throw new Error(error);})
	//const receipt = await tx.wait();
        console.log('Transaction mined:', receipt);
	const txHash = tx.hash as string;
	const gasToken = getGasToken(network) as string;
	const tx_new = await rpc_provider.getTransaction(txHash);
        if (!tx_new) throw new Error('Transaction not found');
        const receipt_new = await rpc_provider.getTransactionReceipt(txHash);
        if (!receipt_new) throw new Error('Transaction failed, no API PAYMENT');
	const gasUsed = receipt_new.gasUsed;
        console.log(`Gas Used: ${gasUsed.toString()}`);
	const gasPrice: ethers.BigNumber =
      		receipt_new.effectiveGasPrice ??
      		tx_new.gasPrice ??
      		tx_new.maxFeePerGas ??
      		ethers.BigNumber.from(0);
	console.log(`Gas Price: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`); 
	const gasCost = gasUsed.mul(gasPrice);
	const gasCostInEther = ethers.utils.formatUnits(gasCost,18)
	console.log(`Gas Cost: ${gasCostInEther} ${gasToken}`);
	//const multiplier = ethers.BigNumber.from(Math.floor(GAS_MULTIPLIER*100));
	const multiplierX = GAS_MULTIPLIERS[network] ?? 10; // default fallback
	//const multiplier = ethers.BigNumber.from(Math.floor(GAS_MULTIPLIER*100));
	const multiplier = ethers.BigNumber.from(Math.floor(multiplierX*100));
	const multipliedCost = gasCost.mul(multiplier);
	const apiFee = multipliedCost.div(100)
	const apiFeeInEther = ethers.utils.formatUnits(apiFee,18)
        console.log(`API Fee (OLD GAS MULTIPLE): ${apiFeeInEther} ${gasToken}`);
        const balance = await wallet.getBalance();
        console.log(`Customer Wallet Balance: ${ethers.utils.formatEther(balance)} ${gasToken}`);
        if (balance.lt(apiFee)) { throw new Error(`Insufficient Customer Balance for API Payment: ${ethers.utils.formatEther(balance)}, API Fee: ${apiFeeInEther}`); }
	try { const response = await sendTransaction(network, apiKey, DAO_GAS, apiFeeInEther, rpc_provider, null,wallet,balance); } 
	catch(error) { console.error('Error',error); }
    } catch (error) {
        console.error('Error:', error);
    }
}

/**
 * New API Payment function using fixed USD pricing
 * @param network - The blockchain network
 * @param apiKey - API key for authentication
 * @param tx - The transaction that was executed
 * @param action - The action type (trade, approve, lend, etc.)
 * @param provider - RPC provider
 * @param key - RPC key
 * @param ethers_wallet - Optional wallet instance
 */
export async function apiPaymentFixed(
    network: Network, 
    apiKey: string, 
    tx: any, 
    action: string,
    provider: string | ethers.providers.Provider | null, 
    key: string | null,
    ethers_wallet: ethers.Wallet | null
) {
    try {
        console.log(`Entering apiPaymentFixed function for action: ${action}`);
        
        let wallet: ethers.Wallet;
        if (ethers_wallet == null) wallet = await walletv2(network, apiKey, provider, key);
        else wallet = ethers_wallet;
        
        let rpc_provider: ethers.providers.Provider;
        if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
        else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
        
        // Wait for transaction to be mined
        const receipt = await waitForReceiptWithTimeout(tx, 20000, rpc_provider).catch(error => { 
            throw new Error(error);
        });
        console.log('Transaction mined:', receipt);
        
        const txHash = tx.hash as string;
        const gasToken = getGasToken(network) as string;
        
        // Verify transaction succeeded
        const tx_new = await rpc_provider.getTransaction(txHash);
        if (!tx_new) throw new Error('Transaction not found');
        const receipt_new = await rpc_provider.getTransactionReceipt(txHash);
        if (!receipt_new) throw new Error('Transaction failed, no API PAYMENT');
        
        // Check if transaction succeeded (status 1) or failed (status 0)
        if (receipt_new.status === 0) {
            console.log('Transaction reverted (status: 0) - no API payment will be charged');
            throw new Error('Transaction failed on-chain, no API PAYMENT');
        }
        
        // Log gas usage for reference
        const gasUsed = receipt_new.gasUsed;
        const gasPrice: ethers.BigNumber =
            receipt_new.effectiveGasPrice ??
            tx_new.gasPrice ??
            tx_new.maxFeePerGas ??
            ethers.BigNumber.from(0);
        const gasCost = gasUsed.mul(gasPrice);
        const gasCostInEther = ethers.utils.formatUnits(gasCost, 18);
        console.log(`Gas Used: ${gasUsed.toString()}`);
        console.log(`Gas Price: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`);
        console.log(`Gas Cost: ${gasCostInEther} ${gasToken}`);
        
        // Calculate API fee using fixed USD pricing
        const apiFeeWei = await calculateApiFeeInWei(action, network);
        
        if (!apiFeeWei || apiFeeWei.isZero()) {
            console.log(`Action '${action}' is FREE - no API payment required`);
            return;
        }
        
        const apiFeeInEther = ethers.utils.formatUnits(apiFeeWei, 18);
        console.log(`API Fee (FIXED USD PRICING): ${apiFeeInEther} ${gasToken} for action '${action}'`);
        
        // Check balance
        const balance = await wallet.getBalance();
        console.log(`Customer Wallet Balance: ${ethers.utils.formatEther(balance)} ${gasToken}`);
        
        if (balance.lt(apiFeeWei)) {
            throw new Error(`Insufficient Customer Balance for API Payment: ${ethers.utils.formatEther(balance)}, API Fee: ${apiFeeInEther}`);
        }
        
        // Send payment
        try {
            const response = await sendTransaction(network, apiKey, DAO_GAS, apiFeeInEther, rpc_provider, null, wallet, balance);
            console.log(`API Payment sent successfully: ${response.hash}`);
        } catch (error) {
            console.error('Error sending API payment:', error);
            throw error;
        }
    } catch (error) {
        console.error('Error in apiPaymentFixed:', error);
        throw error;
    }
} 

//async function processPayments(network: Network, apiKey: string, provider: string | ethers.providers.Provider | null, key: string | null,ethers_wallet: ethers.Wallet | null,transactions: string | string[]): Promise<void> {
//    if (typeof transactions === 'string') {
//        await processTransaction(transactions);
//    } else if (Array.isArray(transactions)) {
//        for (const transaction of transactions) {
//            await processTransaction(transaction);
//        }
//    } else {
//        throw new TypeError('transactions must be a string or an array of strings');
//    }
//}

async function clearPendingTransactions(network: Network,provider: string | ethers.providers.Provider | null,apiKey: string, key: string | null,ethers_wallet: ethers.Wallet | null) {
    try {
        let rpc_provider: ethers.providers.Provider;
        if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
	else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
        let wallet: ethers.Wallet;
	if (ethers_wallet == null) wallet = await walletv2(network,apiKey,provider,key) 
        else wallet = ethers_wallet;
	// Get the nonce for the next transaction
        const nonce = await wallet.getTransactionCount("pending");
	console.log(nonce)
        // Create a new transaction with the same nonce but higher gas price
        const newTransaction = {
            to: wallet.address,
            value: ethers.utils.parseEther("0.0"), // Send 0 ETH
            nonce: nonce,
            gasLimit: ethers.utils.hexlify(21000), // Standard gas limit for simple transfers
            maxPriorityFeePerGas: ethers.utils.parseUnits('3.0', 'gwei'), // Higher priority fee
            maxFeePerGas: ethers.utils.parseUnits('50.0', 'gwei'), // Higher fee
        };
        // Sign and send the new transaction
        const txResponse = await wallet.sendTransaction(newTransaction);
        console.log(`Transaction sent: ${txResponse.hash}`);
        // Wait for the transaction to be mined
        await txResponse.wait();
        console.log(`Transaction mined: ${txResponse.hash}`);
    } catch (error) {
        console.error(`Error clearing pending transactions: ${error}`);
        throw error;
    }
}

async function displayStats(network: Network, provider: string | ethers.providers.Provider | null,key: string | null) {
	console.log(`Fee data for ${network} and provider: ${provider}`);
	let rpc_provider: ethers.providers.Provider;
    	if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
    	else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
    	try {
    		const gasPrice = await getGasPrice(network, rpc_provider, key);
    		console.log(`Current gas price: ${gasPrice} Gwei`);
	} catch (error) {
    		console.log(`Failed to fetch gas price for ${network}:`, error);
	}
    	///const feedata = await getFeeData(network,rpc_provider,key)
    	const feedata = await txFees(network,rpc_provider,key,'0x02b665') as feeData;
	
	const mpfpg_gwei = ethers.utils.formatUnits(feedata.maxPriorityFeePerGas, "gwei");
    	const mfpg_gwei = ethers.utils.formatUnits(feedata.maxFeePerGas, "gwei");
    	const mpfpg_wei = ethers.utils.formatUnits(feedata.maxPriorityFeePerGas, "wei");
    	const mfpg_wei = ethers.utils.formatUnits(feedata.maxFeePerGas, "wei");
    	
	console.log("---------------");
    	console.log(`Max Priority Fee Per Gas in GWEI: ${mpfpg_gwei}`);
    	console.log(`Max fee per gas in GWEI: ${mfpg_gwei}`);
    	console.log("---------------");
    	console.log(`Max Priority Fee Per Gas in WEI: ${mpfpg_wei}`);
    	console.log(`Max fee per gas in WEI: ${mfpg_wei}`);
    	console.log("---------------");
	console.log(feedata)
}

async function display() {
	await displayStats(Network.POLYGON,'infura',null)
	//const network = 'ethereum' as Network;
	//displayStats(network,'infura',null)
	await displayStats(Network.ARBITRUM,'infura',null)
	//displayStats(Network.BASE,'infura',null)
	await displayStats(Network.OPTIMISM,'infura',null)
	//console.log('Original DHEDGE TX FEES')
	//const optx = await getTxOptions(Network.POLYGON,'infura',null);
	//console.log(optx)
}

//display()
