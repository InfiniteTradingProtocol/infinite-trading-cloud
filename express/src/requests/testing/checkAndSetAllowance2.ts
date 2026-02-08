import { ethers } from 'ethers';

// Replace these with actual values
const USDC_E_ADDRESS = '0x2791bca1f2de4661ed88a30c99a7a9449aa84174'; // USDC.e address on Polygon
const WBTC_ADDRESS = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6'; // WBTC address on Polygon
const VAULT_ADDRESS = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6'; // The dHEDGE vault address
const TRADER_WALLET_ADDRESS = '0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5'; // The trader wallet address
const UNISWAP_V3_ROUTER_ADDRESS = '0xE592427A0AEce92De3Edee1F18E0157C05861564'; // Uniswap V3 Router on Polygon
const INFURA_PROJECT_ID = 'd18c6d8db1024751a822f8b8b208737a';

// Connect to Polygon using Ethers.js provider
const provider = new ethers.providers.InfuraProvider('matic', INFURA_PROJECT_ID);

// The ERC20 ABI to check allowance and approve
const ERC20_ABI = [
  'function allowance(address owner, address spender) external view returns (uint256)',
];

// Create a contract instance for USDC.e (replace with WBTC as needed)
const usdcEContract = new ethers.Contract(USDC_E_ADDRESS, ERC20_ABI, provider);

async function checkAllowanceForDApp() {
  try {
    // Check allowance of the dHEDGE pool (vault) to spend USDC.e for UniswapV3 router
    const allowanceUSDC = await usdcEContract.allowance(TRADER_WALLET_ADDRESS, UNISWAP_V3_ROUTER_ADDRESS);

    console.log(`Allowance of USDC.e for UniswapV3 Router: ${allowanceUSDC.toString()}`);

    // If the allowance is 0, the vault hasn't approved the router to spend USDC.e
    if (allowanceUSDC.eq(ethers.BigNumber.from('0'))) {
      console.log('Allowance for USDC.e is zero. Trader cannot trade USDC.e through UniswapV3 Router.');
    } else {
      console.log('Sufficient USDC.e allowance. Trader can trade USDC.e through UniswapV3 Router.');
    }

    // Create a WBTC contract instance and check its allowance similarly
    const wbtcContract = new ethers.Contract(WBTC_ADDRESS, ERC20_ABI, provider);
    const allowanceWBTC = await wbtcContract.allowance(VAULT_ADDRESS, UNISWAP_V3_ROUTER_ADDRESS);

    console.log(`Allowance of WBTC for UniswapV3 Router: ${allowanceWBTC.toString()}`);

    if (allowanceWBTC.eq(ethers.BigNumber.from('0'))) {
      console.log('Allowance for WBTC is zero. Trader cannot trade WBTC through UniswapV3 Router.');
    } else {
      console.log('Sufficient WBTC allowance. Trader can trade WBTC through UniswapV3 Router.');
    }
  } catch (error) {
    console.error('Error checking allowance:', error);
  }
}

checkAllowanceForDApp();

