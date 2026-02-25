import { ethers, Contract } from "ethers";
import { rpc,Network } from "../index";
import * as dotenv from "dotenv";
import path from "path";
dotenv.config({ path: path.resolve(__dirname, "../.env") });

const apiKey =  process.env.INFURA_PROJECT_ID!;

//npm add ethers @bgd-labs/aave-address-book

import {
  AaveV3Ethereum,
  AaveV3Polygon,
  AaveV3Arbitrum,
  AaveV3Optimism,
  AaveV3Base,
  AaveV3Scroll,
} from "@bgd-labs/aave-address-book";

const providersByChainId: Record<number, string> = {
  1: AaveV3Ethereum.POOL_ADDRESSES_PROVIDER,
  10: AaveV3Optimism.POOL_ADDRESSES_PROVIDER,
  137: AaveV3Polygon.POOL_ADDRESSES_PROVIDER,
  42161: AaveV3Arbitrum.POOL_ADDRESSES_PROVIDER,
  8453: AaveV3Base.POOL_ADDRESSES_PROVIDER,
  534352: AaveV3Scroll.POOL_ADDRESSES_PROVIDER,
  // add others from the package as needed
};

const IAddressesProviderAbi = [
  "function getPool() external view returns (address)",
];

const IPoolAbi = [
  "function getUserAccountData(address user) external view returns (uint256 totalCollateralBase,uint256 totalDebtBase,uint256 availableBorrowsBase,uint256 currentLiquidationThreshold,uint256 ltv,uint256 healthFactor)",
];

export async function getAaveV3HealthFactor(
  userAddress: string,
  network: `${Network}`,
  provider: string | null, 
  apiKey: string | null
) {
  const rpc_provider = new ethers.JsonRpcProvider(rpc(network,provider,apiKey));
  const { chainId } = await rpc_provider.getNetwork();

  const providerAddress = providersByChainId[Number(chainId)];
  if (!providerAddress) {
    throw new Error(
      `Chain ${chainId} not in mapping. Use Option B with a PoolAddressesProvider address.`
    );
  }

  const addressesProvider = new ethers.Contract(
    providerAddress,
    IAddressesProviderAbi,
    rpc_provider
  );
  const poolAddress: string = await addressesProvider.getPool();

  const pool = new ethers.Contract(poolAddress, IPoolAbi, rpc_provider);
  const data = await pool.getUserAccountData(userAddress);

  // healthFactor is a RAY (1e18)
  const healthFactor = Number(ethers.formatUnits(data.healthFactor, 18));

  return {
    //chainId: Number(chainId),
    //poolAddress,
    healthFactor,
    //raw: data,
  };
}

// Example:
(async () => {
   const out = await getAaveV3HealthFactor("0xe51af0ba747b9c464057b9099040f4df0b29a7de", "optimism","infura",apiKey);
   console.log(out);
 })();

