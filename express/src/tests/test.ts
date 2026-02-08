import { ethers } from 'ethers';

// Infura URL for Polygon Mainnet
const INFURA_URL = 'https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a';

// Your wallet address
const WALLET_ADDRESS = '0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5';

// Provider initialization (Infura Polygon provider)
const provider = new ethers.providers.JsonRpcProvider(INFURA_URL);

// Function to check nonce and balance
async function checkWalletDetails() {
  try {
    // Get current nonce for the wallet (for pending transactions)
    const nonce = await provider.getTransactionCount(WALLET_ADDRESS, 'pending');
    console.log('Current nonce (pending transactions):', nonce);

    // Get current balance of the wallet
    const balance = await provider.getBalance(WALLET_ADDRESS);
    console.log('Wallet balance (in MATIC):', ethers.utils.formatEther(balance));
  } catch (error) {
    console.error('Error fetching wallet details:', error);
  }
}

// Call the function to check nonce and balance
checkWalletDetails();

