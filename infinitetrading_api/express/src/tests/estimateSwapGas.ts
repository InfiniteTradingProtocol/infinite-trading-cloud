import { ethers } from 'ethers';

// Connect to the Ethereum network
const provider = new ethers.providers.JsonRpcProvider('https://optimism-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a');

// Uniswap V2 Router contract address and ABI
const uniswapRouterAddress = '0xCb1355ff08Ab38bBCE60111F1bb2B784bE25D7e8';
//const uniswapRouterABI = [
//    'function swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline) external payable returns (uint[] amounts)'
//];
const uniswapRouterABI = [
    'function getAmountsOut(uint amountIn, address[] path) external view returns (uint[] amounts)',
    'function swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline) external payable returns (uint[] amounts)'
];
// Create a contract instance
const uniswapRouter = new ethers.Contract(uniswapRouterAddress, uniswapRouterABI, provider);

async function estimateGasForSwap(sender: string, from: string, to: string, amount: string, slippage: number) {
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from the current Unix time
    const path = [from, to];
    const amountToSend = ethers.utils.parseEther(amount); // Convert amount to wei
    const estimatedAmountOut = await uniswapRouter.functions.getAmountsOut(amountToSend, path);
    console.log(estimatedAmountOut);
    console.log(typeof estimatedAmountOut[estimatedAmountOut.length - 1]);
    console.log(JSON.stringify(estimatedAmountOut, null, 2));
    const finalAmountOut = estimatedAmountOut.amounts[1];
    //const finalAmountOut = estimatedAmountOut[estimatedAmountOut.length - 1];
    console.log(finalAmountOut);  // Log the BigNumber object
    console.log(finalAmountOut.mul);  // Log the 'mul' function to check its existence
    //const finalAmountOut = estimatedAmountsOut[1]; // Directly access the output if path length is 2
    //console.log(finalAmountOut);
    const slippageMultiplier = ethers.BigNumber.from(10000 - slippage * 100); // Slippage as a BigNumber
    const amountOutMin = finalAmountOut.mul(slippageMultiplier).div(10000); // Apply slippage
    let estimatedGas;
    try {
        estimatedGas = await uniswapRouter.estimateGas.swapExactTokensForTokens(
            amountOutMin,
            path,
            sender,
            deadline,
            { value: amountToSend } // Send the specified amount of ETH
        );
        console.log(`Estimated Gas Limit: ${estimatedGas.toString()}`);
    } catch (error) {
        console.error(`Error estimating gas: ${error}`);
    }
}

estimateGasForSwap('0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5', '0x7f5c764cbc14f9669b88837ca1490cca17c31607', '0x68f180fcce6836688e9084f035309e29bf0a2095', '0.25', 2).catch(console.error);

