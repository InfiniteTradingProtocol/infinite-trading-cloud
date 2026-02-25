const ethers = require('ethers');

async function clearNonce() {
  const provider = new ethers.providers.JsonRpcProvider('https://optimism-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a');
  
  const privateKey = '0x' + process.env.PRIVATE_KEY;
  const wallet = new ethers.Wallet(privateKey, provider);
  
  console.log('Wallet address:', wallet.address);
  
  const currentNonce = await provider.getTransactionCount(wallet.address, 'pending');
  console.log('Current pending nonce:', currentNonce);
  
  const tx = {
    to: wallet.address,
    value: ethers.utils.parseEther('0'),
    nonce: 5923,
    maxPriorityFeePerGas: ethers.utils.parseUnits('0.1', 'gwei'),
    maxFeePerGas: ethers.utils.parseUnits('1', 'gwei'),
    gasLimit: 21000,
    type: 2
  };
  
  console.log('Sending replacement tx with nonce 5923...');
  console.log('MaxPriorityFee:', ethers.utils.formatUnits(tx.maxPriorityFeePerGas, 'gwei'), 'gwei');
  console.log('MaxFee:', ethers.utils.formatUnits(tx.maxFeePerGas, 'gwei'), 'gwei');
  
  const txResponse = await wallet.sendTransaction(tx);
  console.log('Replacement tx hash:', txResponse.hash);
  console.log('Waiting for confirmation...');
  
  const receipt = await txResponse.wait();
  console.log('Confirmed! Block:', receipt.blockNumber);
  console.log('Nonce 5923 cleared!');
}

clearNonce().catch(console.error);
