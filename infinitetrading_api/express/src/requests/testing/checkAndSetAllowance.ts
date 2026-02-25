import { ethers } from 'ethers';

// Replace these with actual values
const WBTC_ADDRESS = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174'; // USDC.e address on Polygon
const VAULT_ADDRESS = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6'; // The dHEDGE vault address
const TRADER_WALLET_ADDRESS = '0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5'; // The trader wallet address
const INFURA_PROJECT_ID = 'd18c6d8db1024751a822f8b8b208737a'; // Your Infura project ID

// Connect to Polygon using Ethers.js provider
const provider = new ethers.providers.InfuraProvider('matic', INFURA_PROJECT_ID);

// The WBTC contract ABI for the allowance and approve functions
const ERC20_ABI = [
  'function allowance(address owner, address spender) external view returns (uint256)',
  'function approve(address spender, uint256 amount) external returns (bool)'
];

// Create a contract instance for WBTC
const wbtcContract = new ethers.Contract(WBTC_ADDRESS, ERC20_ABI, provider);

async function checkAndSetAllowance() {
  try {
    // Get the current allowance for the trader wallet in the vault
    const currentAllowance = await wbtcContract.allowance(TRADER_WALLET_ADDRESS,VAULT_ADDRESS);
    
    console.log('Current Allowance:', currentAllowance.toString());

    // Max uint256 value to compare for infinite allowance
    const MAX_UINT256 = ethers.constants.MaxUint256;
    console.log(currentAllowance)
    // Check if allowance is infinite
    if (currentAllowance.eq(MAX_UINT256)) {
      console.log('Allowance is already infinite.');
    } else {
      console.log('Allowance is not infinite, setting infinite allowance...');

      // If allowance is not infinite, create a signer to approve it
      //const signer = provider.getSigner(VAULT_ADDRESS); // Replace with the correct signer
      
      // Send an approval transaction to set infinite allowance
      //const tx = await wbtcContract.connect(signer).approve(TRADER_WALLET_ADDRESS, MAX_UINT256);
      
      // Wait for the transaction to be confirmed
      //await tx.wait();

      //console.log('Infinite allowance set successfully.');
    }
  } catch (error) {
    console.error('Error checking or setting allowance:', error);
  }
}

checkAndSetAllowance();

