import { ethers, Network } from "@dhedge/v2-sdk";
import { BigNumber } from "ethers";

// Corrected to include ERC20 ABI as a parameter
//require("dotenv").config();
require("dotenv").config({ path: "../../../.env" });
const wallet = (network: Network,manager: string| null = null): ethers.Wallet => {
  let url;
  switch (network) {
    case "polygon":
      url = `https://polygon-mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`;
      break;
    case "optimism":
      url = `https://optimism-mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`;
      break;
    case "arbitrum":
      url = `https://arbitrum-mainnet.infura.io/v3/${process.env.INFURA_PROJECT_ID}`;
      break;
    default:
      throw Error("network not supported");
  }
    let privateKey;
  if (manager === null) {
        // Use default private key when manager is null
        privateKey = process.env.PRIVATE_KEY as string;
  } else {
        // Retrieve private key from .env file based on manager
        const privateKEyEnvVarName = `PRIVATE_KEY_${manager}`
          privateKey = process.env[privateKEyEnvVarName] as string;
        if (!privateKey) {
                privateKey = process.env.PRIVATE_KEY as string;
                //throw Error(`Private key not found for manager: ${manager}`);
        }
  }
  return new ethers.Wallet(
    privateKey,
    new ethers.providers.JsonRpcProvider(url)
  );
};
const manager = "infinitetrading"
console.log(`INFURA_PROJECT_ID: ${process.env.INFURA_PROJECT_ID}`);
console.log(`Default PRIVATE_KEY: ${process.env.PRIVATE_KEY}`);
const privateKEyEnvVarName = `PRIVATE_KEY_${manager}`;
console.log(`${privateKEyEnvVarName}: ${process.env[privateKEyEnvVarName]}`);

async function checkallowance(assetAddress: string, contractAddress: string, amount: BigNumber, erc20ABI: any, signer: ethers.Signer) {
    // Parse the ABI if it's a string (it should be an object or array)
    const provider = new ethers.providers.JsonRpcProvider("https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a");
    const parsedErc20ABI = JSON.parse(erc20ABI);
    const tokenContract = new ethers.Contract(assetAddress, parsedErc20ABI, provider);
    const allowed = await tokenContract.allowance(await signer.getAddress(), contractAddress);

    let isAllowed: boolean = !amount.lt(allowed);
    if (!isAllowed) {
        console.log('You need to approve the contract to use your tokens.');
        // Approve transaction goes here
    } else {
        console.log('Allowance is sufficient. Proceeding with the trades...');
        // Staking code goes here
    }
    return isAllowed
}
//const provider = new ethers.providers.JsonRpcProvider("https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a");
//const contractAddress = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6';
//const erc20ABI = '[{"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}]';
//const parsedErc20ABI = JSON.parse(erc20ABI);
//const contract = new ethers.Contract(contractAddress, parsedErc20ABI, provider);
// Example method name and arguments
//const recipient = '0x41ce39FF9a2520779c9eBa4a718de8973e62551F';
//const amount = ethers.utils.parseEther('1'); // For example, 1 token
// Function to list all state-changing functions from the ABI

async function estimateGasForMethod() {
  try {
    const gasEstimate = await contract.estimateGas.transfer(recipient, amount, {
      // Optional overrides here, e.g., { gasPrice: 1000000000 }
    });

    console.log(`Estimated Gas: ${gasEstimate.toString()}`);
    return gasEstimate;
  } catch (error) {
    console.error('Error estimating gas:', error);
    throw error;
  }
}

(async () => {
    const assetAddress = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6';
    const contractAddress = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6';
    const amount = ethers.utils.parseEther("100");
    console.log(amount)
    // The network variable was removed since it's not used in this scope.
    const erc20ABI = '[{"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}]'; // Simplified ABI for demonstration
    const manager = 'infinitetrading'; // Ensure you have this function correctly defined to return a signer
    let network = Network.POLYGON;
    const signer = wallet(network,manager); // Assuming wallet returns a correctly initialized ethers.Signer
    await checkallowance(assetAddress, contractAddress, amount, erc20ABI, signer);
    //estimateGasForMethod();
})();

