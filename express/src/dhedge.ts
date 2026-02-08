import { Dhedge, Network } from "@dhedge/v2-sdk";
import { wallet } from "./wallet";
import { walletv2 } from "./walletv2";

export const dhedge = (network: Network, manager: string | null = null): Dhedge => {
	let mywallet;
	mywallet = wallet(network, manager);
	//console.log("using manager wallet")
	//console.log(mywallet)
	return new Dhedge(mywallet, network);
}

export const dhedgev2 = async (network: Network, apiKey: string, provider: string | null = null, key: string | null = null): Promise<Dhedge> => {
  return new Dhedge(await walletv2(network, apiKey, provider, key), network);
};

//const network = 'polygon' as Network;
//const apiKey = '0e5be968b6cac0fa61c9ab89db2ff84e2b198dc94dd331ccacea98cbafe490b1fae0779825d56261c4b1d6994943788ed1ae1e12db9d52e345c5b8cbfdadb988' as string;
//let provider = null;
//let key = null;

//(async () =>
// { const dhedgeInstance = await dhedgev2(network, apiKey, provider, key);
// console.log(dhedgeInstance)
// })();
