import { ethers } from 'ethers';

// Infura URL and Wallet Setup
//const INFURA_URL = 'https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a';
const INFURA_URL = 'https://polygon-mainnet.g.alchemy.com/v2/QR_eaiUU1cqvUYuwkyoUusEek2HCjV_J';
const PRIVATE_KEY = 'df4730a2cd828b96f7a65214e93168c00d3654a526f664d8152302467c892898'; // Your private key
const walletAddress = '0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5';

const provider = new ethers.providers.JsonRpcProvider(INFURA_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

async function replacePendingTransaction() {
  try {
    // Get the current nonce for pending transactions
    const nonce = await provider.getTransactionCount(walletAddress, 'pending');
    console.log('Replacing pending transaction with nonce:', nonce);

    // Create a replacement transaction (send 0 MATIC, with a higher gas fee)
    const tx = {
      to: walletAddress, // Replace with your own address to "self-send"
      value: ethers.utils.parseEther('0'), // Sending 0 MATIC to yourself
      gasLimit: ethers.utils.hexlify(50000), // Small gas limit
      maxPriorityFeePerGas: ethers.utils.parseUnits('100', 'gwei'), // Priority fee (increase this)
      maxFeePerGas: ethers.utils.parseUnits('200', 'gwei'), // Max fee per gas (increase this)
      nonce, // Set the same nonce as the pending transaction
      type: 2, // EIP-1559 transaction type
    };

    // Send the replacement transaction
    const txResponse = await wallet.sendTransaction(tx);
    console.log('Replacement transaction sent:', txResponse);

    // Wait for the transaction to be mined
    const receipt = await txResponse.wait();
    console.log('Replacement transaction confirmed:', receipt);
  } catch (error) {
    console.error('Error replacing transaction:', error);
  }
}

// Execute the replacement
replacePendingTransaction();

