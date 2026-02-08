import { ethers } from 'ethers';

// Connect to the Ethereum network
const provider = new ethers.providers.JsonRpcProvider('https://mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a');

// Uniswap V2 Router contract address and ABI (simplified)
const uniswapRouterAddress = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D'; // Example address, replace with actual
const uniswapRouterABI = [
    'function swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline) external payable returns (uint[] amounts)'
];

// Create a contract instance
const uniswapRouter = new ethers.Contract(uniswapRouterAddress, uniswapRouterABI, provider);

async function estimateGasForSwap(sender:string, from: string,to: string,platform: string) {
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from the current Unix time
    const path = [from, to];
    const amountOutMin = 1; // Minimum amount of tokens to receive (example value)

    // Estimate the gas limit
    if (platform == 'uniswapV3') { 
    	const estimatedGas = await uniswapRouter.estimateGas.swapExactETHForTokens(
        	amountOutMin,
        	path,
        	sender,
        	deadline,
        	{ value: ethers.utils.parseEther("1.0") } // Sending 1 ETH
    	)
    }
    console.log(`Estimated Gas Limit: ${estimatedGas.toString()}`);
}

estimateGasForSwap('0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5','0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2','0xdac17f958d2ee523a2206206994597c13d831ec7','uniswapV3').catch(console.error);

