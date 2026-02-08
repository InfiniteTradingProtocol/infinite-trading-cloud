import { ethers, Network } from "@dhedge/v2-sdk";
import { BigNumber } from "ethers"
import { wallet } from "../../wallet";
async function checkAllowance(tokenContractAddress: string, spenderAddress: string, ownerAddress: string) {
    // Connect to the ERC-20 token contract
    const provider = new ethers.providers.JsonRpcProvider("https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a") 
    const tokenContract = new ethers.Contract(tokenContractAddress, erc20ABI, provider);
    
    // Call the allowance method to get the allowance
    const allowance = await tokenContract.allowance(ownerAddress, spenderAddress);

    return allowance;
}


async function checkAndStakeTokens(assetAddress, contractAddress, amount, erc20ABI, signer) {
  // Check if the allowance is sufficient
  
  const Allowed = await checkAllowance(assetAddress, signer.getAddress(), contractAddress);
  let isAllowed: boolean;
  isAllowed = !amount.lt(Allowed)
  if (!isAllowed) {
    // User needs to approve the staking contract to spend tokens
    console.log('You need to approve the contract to use your tokens.');
    // Here, you'd typically invoke the approve function
  } else {
    // Proceed with staking
    console.log('Allowance is sufficient. Proceeding with staking...');
    // Code to stake the tokens
  }
}
// Example usage
(async () => {
    // Example parameters - replace these with actual values
    const assetAddress = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6'; // ERC-20 token address
    const contractAddress = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6'; // Staking contract address
    const amount = ethers.utils.parseEther("100"); // For example, staking 100 tokens
    const network=Network.POLYGON
    const erc20ABI = '[{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"implementation","type":"address"}],"name":"Upgraded","type":"event"},{"stateMutability":"payable","type":"fallback"},{"inputs":[{"internalType":"address","name":"_factory","type":"address"},{"internalType":"bytes","name":"_data","type":"bytes"},{"internalType":"uint8","name":"_proxyType","type":"uint8"}],"name":"initialize","outputs":[],"stateMutability":"payable","type":"function"},{"stateMutability":"payable","type":"receive"}]';
    const manager = 'infinitetrading'
    const signer = wallet(network,manager)
    // Invoke the function
    await checkAndStakeTokens(assetAddress, contractAddress, amount, erc20ABI, signer);
})();
