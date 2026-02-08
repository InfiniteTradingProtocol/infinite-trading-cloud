import { Network } from "@dhedge/v2-sdk";
import * as path from 'path';
require("dotenv").config({ path: '../.env' });

export function rpc(network: Network, provider: string | null = null,key: string | null = null): string {
        let apiKey;
        let url; let word;
        if (provider == null) { provider = 'alchemy' }
        switch (provider) {
		case 'alchemy':
			if (key == null) {
				apiKey = process.env.ALCHEMY_API_KEY as string;
				if (!apiKey) { throw new Error("No ALCHEMY_API_KEY in the .env file found") }
			}
			else { apiKey = key }
			switch (network) {
				case Network.ETHEREUM:
					word = 'eth';
					break;
				case Network.ARBITRUM:
			       		word = 'arb';
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
			switch (network) {
                                case Network.ETHEREUM:
                                        url = `https://mainnet.infura.io/v3/${apiKey}`;
					break;
				default: 
					url = `https://${network}-mainnet.infura.io/v3/${apiKey}`;
                        		break;
			}
                case 'drpc':
                        if (key == null) {
                                apiKey = process.env.dRPC_API_KEY as string;
                                if (!apiKey) { throw new Error("No dRPC_API_KEY in the .env file found"); }
                        }
                        else {
                                apiKey = key
                        }
                        url = `https://lb.drpc.org/${network}/${apiKey}`
                        break;
                default:
                        if (key == null) {
                                apiKey = process.env.ALCHEMY_API_KEY as string;
                                if (!apiKey) { throw new Error("No ALCHEMY_API_KEY in the .env file found") }
                        }
                        else { apiKey = key }
                        switch (network) {
                                case Network.ARBITRUM:
                                        word = 'arb';
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
        }
        return url;
};


// Test scripts

//const network = 'ethereum' as Network;
//const key = 'AupHsm6YrU4Wkxg2M1Vgrvc6uSbSNY4R76U3hkHL9tz4';
//const provider_name = 'infura';
//const url = rpc(Network.BASE,'alchemy',null)
//console.log(url)
//const url2 = rpc(network)

//const url3 = rpc(network,provider_name)

//console.log(url)
//console.log(url2)
//console.log(url3)

//const provider = "infura" as string;
//console.log(rpc(network,provider_name))
