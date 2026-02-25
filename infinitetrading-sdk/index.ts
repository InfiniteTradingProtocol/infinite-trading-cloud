import { ethers, formatUnits } from "ethers";
import * as dotenv from "dotenv";
dotenv.config();

const networkConfig = {
  mainnet: {
    chainId: 1,
    name: 'mainnet',
    nativeCurrency: 'ETH'
  },
  polygon: {
    chainId: 137,
    name: 'polygon',
    nativeCurrency: 'MATIC'
  },
  arbitrum: {
    chainId: 42161,
    name: 'arbitrum',
    nativeCurrency: 'ETH'
  },
  optimism: {
    chainId: 10,
    name: 'optimism',
    nativeCurrency: 'ETH'
  },
  base: {
    chainId: 8453,
    name: 'base',
    nativeCurrency: 'ETH'
  },
  ink: { 
    chainId: 57073,
    name: 'ink',
    nativeCurrency: 'ETH'
  },
  unichain: {
    chainId: 130,
    name: 'unichain',
    nativeCurrency: 'ETH'
  }
};

export enum Network {
  POLYGON = "polygon",
  OPTIMISM = "optimism",
  ARBITRUM = "arbitrum",
  BASE = "base",
  ETHEREUM = "ethereum",
  LISK = "lisk",
  MODE = "mode",
  FRAXTAL = "fraxtal",
  INK = "ink",
  UNICHAIN = "unichain"
}
export function formatAmount(amount: string, decimals = 18): string {
    return formatUnits(amount, decimals);
}
export function formatDate(timestamp: bigint): string {
    return new Date(Number(timestamp) * 1000).toISOString();
}
export function getUSDC_Address(network: `${Network}`): string {
        // Initialize the contract ONLY OP IS CORRCT, FIX ADDRESSES FOR THE REST
        // ink and unichain USDC is bridged and not native
	// update later if they remove bridged.
	let USDC_ADDRESS: string;
        switch (network) {
            case "optimism":
                USDC_ADDRESS = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85";
                break;
            case "base":
                USDC_ADDRESS = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
                break;
            case "fraxtal":
                USDC_ADDRESS = "0xdcc0f2d8f90fde85b10ac1c8ab57dc0ae946a543";
                break;
            case "lisk":
                USDC_ADDRESS = "0xf242275d3a6527d877f2c927a82d9b057609cc71";
                break;
            case "mode":
                USDC_ADDRESS = "0xd988097fb8612cc24eec14542bc03424c656005f";
                break;
	    case "unichain":
	    	USDC_ADDRESS = "0x078d782b760474a361dda0af3839290b0ef57ad6";
	    	break;
	    case "ink":
	    	USDC_ADDRESS = "0xf1815bd50389c46847f0bda824ec8da914045d14";
		break;
            default:
                throw new Error("Unsupported network specified.");
        }
        return(USDC_ADDRESS)
}

export function rpc(network: `${Network}`, provider: string | null = null,key: string | null = null): string {
        let apiKey;
        let url;
	const nw = network as Network
        if (provider == null) { provider = 'alchemy' }
        switch (provider) {
		case 'alchemy':
			if (key == null) {
				apiKey = process.env.ALCHEMY_API_KEY as string;
				if (!apiKey) { throw new Error("No ALCHEMY_API_KEY in the .env file found") }
			}
			else { apiKey = key }
			let word;
			switch (nw) {
				case Network.ARBITRUM:
			       		word = 'arb';
					break;
				case Network.ETHEREUM:
					word = 'eth';
					break;
				case Network.OPTIMISM:
					word = 'opt';
					break;
				case Network.BASE:
					word = 'base';
					break;
				case Network.POLYGON:
					word = 'polygon';
					break;
				default:
					word = network;
					break;
			}
			url = `https://${word}-mainnet.g.alchemy.com/v2/${apiKey}`;
			break;
                case 'infura':
                        if (key == null) {
                                apiKey = process.env.INFURA_PROJECT_ID as string;
                                if (!apiKey) { throw new Error("No INFURA_PROJECT_ID in the .env file found"); }
                        }
                        else { apiKey = key }
                        if (network == 'ethereum') { url = `https://mainnet.infura.io/v3/${apiKey}` } 
		        else { url = `https://${network}-mainnet.infura.io/v3/${apiKey}` }
                        break;
                case 'drpc':
                        if (key == null) {
                                apiKey = process.env.dRPC_API_KEY as string;
                                if (!apiKey) { throw new Error("No dRPC_API_KEY in the .env file found"); }
                        }
                        else {
                                apiKey = key
                        }
                        url = `https://lb.drpc.org/ogrpc?network=${network}&dkey=${apiKey}`
                        break;
                default:
                                throw new Error('RPC Provider not support');
        }
        return url;
};


// Test scripts

//const url = rpc("optimism",'alchemy',null)
//console.log(url)
