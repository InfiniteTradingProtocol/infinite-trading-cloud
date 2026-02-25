import { ethers } from 'ethers';

// Network configuration
const networkConfig = {
  mainnet: {
    chainId: 1,
    name: 'mainnet',
    rpcUrl: 'https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID',
    nativeCurrency: 'ETH'
  },
  polygon: {
    chainId: 137,
    name: 'polygon',
    rpcUrl: 'https://polygon-rpc.com',
    nativeCurrency: 'MATIC'
  },
  arbitrum: {
    chainId: 42161,
    name: 'arbitrum',
    rpcUrl: 'https://arbitrum-mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID',
    nativeCurrency: 'ETH'
  },
  optimism: {
    chainId: 10,
    name: 'optimism',
    rpcUrl: 'https://optimism-mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID',
    nativeCurrency: 'ETH'
  },
  base: {
    chainId: 8453,
    name: 'base',
    rpcUrl: 'https://base-mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID',
    nativeCurrency: 'ETH'
  }
};

// Replace with your private key
const privateKey = 'YOUR_PRIVATE_KEY';

async function sendGasCostToAnotherWallet(network: string, txHash: string, targetWalletAddress: string) {
  try {
    const config = networkConfig[network];
    if (!config) {
      throw new Error('Unsupported network');
    }

    // Connect to the Ethereum provider
    const provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
    const wallet = new ethers.Wallet(privateKey, provider);

    // Get the transaction details
    const tx = await provider.getTransaction(txHash);
    if (!tx) {
      throw new Error('Transaction not found');
    }

    // Get the transaction receipt to find out the gas used
    const receipt = await provider.getTransactionReceipt(txHash);
    if (!receipt) {
      throw new Error('Transaction receipt not found');
    }

    // Verify that the transaction was successful
    if (receipt.status === 0) {
      throw new Error('Transaction failed');
    }

    // Calculate the gas cost (gas used * gas price)
    const gasUsed = receipt.gasUsed;
    const gasPrice = tx.gasPrice;
    const gasCost = gasUsed.mul(gasPrice);

    // Convert gas cost from wei to ether (or matic)
    const gasCostInEther = ethers.utils.formatEther(gasCost);
    console.log(`Gas cost in ${config.nativeCurrency}: ${gasCostInEther}`);

    // Verify the wallet has enough balance to send the gas cost
    const balance = await wallet.getBalance();
    if (balance.lt(gasCost)) {
      throw new Error(`Insufficient balance. Balance: ${ethers.utils.formatEther(balance)}, Gas cost: ${gasCostInEther}`);
    }

    // Create the transaction to send the gas cost to the target wallet
    const transaction = {
      to: targetWalletAddress,
      value: gasCost,
    };

    // Send the transaction
    const response = await wallet.sendTransaction(transaction);
    console.log(`Transaction sent: ${response.hash}`);

    // Wait for the transaction to be confirmed
    await response.wait();
    console.log('Transaction confirmed');

  } catch (error) {
    console.error('Error:', error);
  }
}

// Example usage with network, transaction hash, and target wallet address
const network = 'polygon'; // Change this to 'mainnet', 'polygon', 'arbitrum', 'base', or 'optimism'
const txHash = 'YOUR_TRANSACTION_HASH';
const targetWalletAddress = 'TARGET_WALLET_ADDRESS';
sendGasCostToAnotherWallet(network, txHash, targetWalletAddress);

