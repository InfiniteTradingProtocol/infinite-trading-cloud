import { ethers, Network } from "@dhedge/v2-sdk";
import { rpc, getAllRpcProviders } from './rpc';
import { exec } from 'child_process';
import { RetryProvider, createRetryProviderWithFailover } from './utils/RetryProvider';
//import { path } from 'path';
import path = require('path');

export async function getProvider(network: Network,provider: string | null, key: string | null) {
    if (provider === null) {
        // Use all available providers for failover
        const providerUrls = getAllRpcProviders(network);
        return createRetryProviderWithFailover(providerUrls);
    } else {
        // Use specific provider
        const providerUrl = rpc(network, provider, key);
        return new RetryProvider(providerUrl);
    }
}

function add0xPrefix(privateKey: string): string {
  if (!privateKey.startsWith('0x')) return '0x' + privateKey;
  return privateKey;
}

async function runRScript(apiKey: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const scriptPath = path.resolve('/home/ubuntu/infinitetrading/src/api/encryption.R'); 
    exec(`Rscript ${scriptPath} ${apiKey}`, (error, stdout, stderr) => {
      if (error) { reject(`error: ${error.message}`); }
      if (stderr) { reject(`stderr: ${stderr}`); }
      resolve(stdout.trim());
    });
  });
}

export async function walletv2(network: Network,apiKey: string,provider: string | ethers.providers.Provider | null = null,key: string| null): Promise<ethers.Wallet> {
        const privateKey = await runRScript(apiKey) as string;
	const full_privateKey = add0xPrefix(privateKey) as string;
	let rpc_provider: ethers.providers.Provider;
        
        if (provider instanceof ethers.providers.Provider) {
            rpc_provider = provider;
        } else if (provider === null) {
            // Use all available providers for failover
            const providerUrls = getAllRpcProviders(network);
            rpc_provider = createRetryProviderWithFailover(providerUrls);
        } else {
            // Use specific provider
            rpc_provider = new RetryProvider(rpc(network, provider, key));
        }
        
  	return new ethers.Wallet(full_privateKey, rpc_provider);
};

//////////////////
// Test scripts
//////////////////

//const network = 'polygon' as Network;
//const apiKey = '79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688' as string;
//const provider = 'infura'

//infura key
//const key = null


//const walletInstance = walletv2(network, apiKey,provider, key);

//console.log(`Wallet address: ${walletInstance.address}`);
//walletv2(network, apiKey, provider, key)
// .then(wallet => {
//   console.log(`Wallet address: ${wallet.address}`);
//   console.log('Wallet object:', JSON.stringify(wallet, null, 2)); // Convert wallet object to JSON string
// })
// .catch(error => {
//   console.error('Failed to create wallet object:', error);
// });
