import { ethers, Network } from "@dhedge/v2-sdk";
require("dotenv").config({ path: '../.env' });

function rpcURL(network: Network, manager: string | null = null): string {
  let provider_key;
  if (manager === null) {
    provider_key = process.env.ALCHEMY_API_KEY as string;
    if (!provider_key) { throw new Error("No ALCHEMY_API_KEY in the .env file found"); }
  } else {
    const provider_keyEnvVarName = `ALCHEMY_API_KEY_${manager}`;
    provider_key = process.env[provider_keyEnvVarName] as string;
    if (!provider_key) {
      provider_key = process.env.ALCHEMY_API_KEY as string;
      if (!provider_key) { throw new Error("No ALCHEMY_API_KEY in the .env file found"); }
    }
  }
  switch (network) {
    case 'polygon':
      return `https://polygon-mainnet.g.alchemy.com/v2/${provider_key}`;
    case 'optimism':
      return `https://opt-mainnet.g.alchemy.com/v2/${provider_key}`;
    case 'arbitrum':
      return `https://arb-mainnet.g.alchemy.com/v2/${provider_key}`;
    case 'base':
      return `https://base-mainnet.g.alchemy.com/v2/${provider_key}`;
    default:
      throw new Error('Network not supported');
  }
};

export const wallet = (network: Network,manager: string| null = null): ethers.Wallet => {
  //console.log(url)
  let privateKey;
  if (manager === null) {
        privateKey = process.env.PRIVATE_KEY;
	if (!privateKey) { throw Error("No PRIVATE_KEY in the .env file found") }
  } else {
        const privateKeyEnvVarName = `PRIVATE_KEY_${manager}`;
	privateKey = process.env[privateKeyEnvVarName];
        if (!privateKey) { privateKey = process.env.PRIVATE_KEY; }
	if (!privateKey) { throw Error("No PRIVATE_KEY in the .env file found") }
  }
  const url = rpcURL(network, manager) as string; // Ensure rpcURL is properly imported and used
  //console.log(privateKey)
  return new ethers.Wallet(privateKey, new ethers.providers.JsonRpcProvider(url));
};
