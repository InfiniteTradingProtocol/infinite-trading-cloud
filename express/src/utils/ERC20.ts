// utils/ERC20.ts
import { rpc } from "../rpc";
import { ethers } from "ethers";
type RpcNetwork = Parameters<typeof rpc>[0];


const ERC20_ABI = ["function decimals() view returns (uint8)"];
// provider = ethers.providers.JsonRpcProvider(...)
export async function getTokenDecimals(tokenAddress: string, network: RpcNetwork, provider: string | null,providerKey: string | null): Promise<number> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(rpc(network, provider, providerKey));
  const erc20 = new ethers.Contract(tokenAddress, ERC20_ABI, rpcProvider);
  const dec: number = await erc20.decimals();
  return Number(dec);
}

