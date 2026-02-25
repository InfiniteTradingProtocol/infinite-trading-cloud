import {ethers} from 'ethers'
/**
 * Gets an estimate for gas limit (units of gas) expressed in Gwei
 * @param {object} dexRouterContract - Contract object of the DEX router 
 * @param {str} tokenInAddress - Address of the input token
 * @param {str} tokenOutAddress - Address of the output token 
 * @param {int} tokenInAmount - Amount of input token denominated in Wei
 * @param {int} tokenOutAmount - Amount of output token denominated in Wei
 * @param {str} userAddress - Address to perform the swap 
 * (PS: Ensure this address has enough of the input and output token as it impacts the gas estimation) 
 * @returns {str} gasLimit - upper gas limit estimation denominated in Gwei
 */
const provider = new ethers.providers.JsonRpcProvider('https://optimism-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a');
const uniswapRouterAddress = '0xCb1355ff08Ab38bBCE60111F1bb2B784bE25D7e8';
//const uniswapRouterABI = [
//    'function swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline) external payable returns (uint[] amounts)'
//];
const uniswapRouterABI = [
    'function getAmountsOut(uint amountIn, address[] path) external view returns (uint[] amounts)',
    'function swapExactETHForTokens(uint amountOutMin, address[] path, address to, uint deadline) external payable returns (uint[] amounts)'
];
const uniswapRouter = new ethers.Contract(uniswapRouterAddress, uniswapRouterABI, provider);
export async function estimateGasLimitForTokenSwap(
        dexRouterContract,
        tokenInAddress,
        tokenOutAddress,
        tokenInAmount,
        tokenOutAmount,
        userAddress,
    ) {
    let now = new Date
    // Uniswap requires a deadline for the swap. 30 minutes from now expressed as milliseconds since epoch 
    const deadline = now.setTime(now.getTime() + (30 * 60 * 1000)) 
    const gasLimit = await dexRouterContract.estimateGas.swapExactTokensForTokens(
        tokenInAmount,
        tokenOutAmount,
        [
            tokenInAddress,
            tokenOutAddress
        ],
        userAddress,
        deadline,
        {
            from: userAddress
        }
    )
    console.log(gasLimit.toString()) 
    return gasLimit.toString()
}

estimateGasLimitForTokenSwap(uniswapRouter,'0x7f5c764cbc14f9669b88837ca1490cca17c31607','0x68f180fcce6836688e9084f035309e29bf0a2095',1,1,'0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5')
