import { ethers } from 'ethers';

async function estimateGas() {
  // Connect to an Ethereum provider (Optimism in this case)
  const provider = new ethers.providers.JsonRpcProvider('https://optimism-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a');

  // Example transaction object
  const transactionObject = {
    from: '0x3ceF74F9eDA6Cf5aE028499bE4B8B50d1b7fc295',
    to: '0xc3f232c00ab6ce31a332126331da3f74ca1d51cc',
    value: ethers.utils.parseEther('1.0'), // Example: 1 ETH
  };

  try {
    // Estimate gas for the transaction
    const gasEstimate = await provider.estimateGas(transactionObject);

    console.log('Gas Estimate:', gasEstimate.toNumber());
  } catch (error) {
    console.error('Error estimating gas:', error.message);
  }
}

// Run the function
estimateGas();

