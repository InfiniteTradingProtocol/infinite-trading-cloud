// utils/aave.ts
import { rpc } from "../rpc";
import { ethers, BigNumber, BigNumberish } from "ethers";
type RpcNetwork = Parameters<typeof rpc>[0];

const IAddressesProviderAbi = [
  "function getPool() external view returns (address)",
];

const IPoolAbi = [
  // indices: 0..5; healthFactor is index 5
  "function getUserAccountData(address user) external view returns (uint256,uint256,uint256,uint256,uint256,uint256)",
];
export interface GetPoolAaveDataRaw {
  totalCollateralBase: BigNumber;        // 1e8
  totalDebtBase: BigNumber;              // 1e8
  availableBorrowsBase: BigNumber;       // 1e8
  currentLiquidationThreshold: BigNumber; // 1e4 (e.g. 7800 => 78.00%)
  ltv: BigNumber;                        // 1e4 (e.g. 7300 => 73.00%)
  healthFactor: BigNumber;               // 1e18 (ray)
}
export interface GetPoolAaveDataFormatted {
  // Strings to avoid JS precision loss
  totalCollateralBase: string;           // base currency (1e8), e.g. "88734.86649469"
  totalDebtBase: string;                 // base currency (1e8)
  availableBorrowsBase: string;          // base currency (1e8)
  currentLiquidationThreshold: string;   // fraction (divide by 1e4), e.g. "0.78"
  ltv: string;                           // fraction (divide by 1e4), e.g. "0.73"
  healthFactor: string;                  // e.g. "2.082315010325651487"
}
export interface GetPoolAaveDataResult {
  //raw: GetPoolAaveDataRaw;
  formatted: GetPoolAaveDataFormatted;
}
function fmt(x: BigNumberish, decimals: number): string {
  return ethers.utils.formatUnits(x, decimals);
}
function pick<T = BigNumber>(
  data: any,
  namedKey: string,
  index: number
): T | undefined {
  if (data && typeof data === "object" && namedKey in data) return (data as any)[namedKey] as T;
  if (Array.isArray(data)) return (data as any[])[index] as T;
  return undefined;
}

export async function getPoolAaveData(
  userAddress: string,
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool OR PoolAddressesProvider
): Promise<GetPoolAaveDataResult> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );

  // Sanity: address must have code
  const code = await rpcProvider.getCode(contractAddress);
  if (code === "0x") {
    throw new Error(`No contract code at ${contractAddress}`);
  }

  // Resolve Pool from AddressesProvider if possible; otherwise treat given address as Pool
  let poolAddress = contractAddress;
  try {
    const addressesProvider = new ethers.Contract(
      contractAddress,
      IAddressesProviderAbi,
      rpcProvider
    );
    const resolved = await addressesProvider.getPool();
    if (resolved && ethers.utils.isAddress(resolved)) {
      poolAddress = resolved;
    }
  } catch {
    // ignore → use contractAddress as Pool
  }
  const pool = new ethers.Contract(poolAddress, IPoolAbi, rpcProvider);
  const data: any = await pool.getUserAccountData(userAddress);
  // getUserAccountData returns (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor)

  const totalCollateralBase =
    pick<BigNumber>(data, "totalCollateralBase", 0) ??
    (() => { throw new Error("totalCollateralBase missing from getUserAccountData"); })();

  const totalDebtBase =
    pick<BigNumber>(data, "totalDebtBase", 1) ??
    (() => { throw new Error("totalDebtBase missing from getUserAccountData"); })();

  const availableBorrowsBase =
    pick<BigNumber>(data, "availableBorrowsBase", 2) ??
    (() => { throw new Error("availableBorrowsBase missing from getUserAccountData"); })();

  const currentLiquidationThreshold =
    pick<BigNumber>(data, "currentLiquidationThreshold", 3) ??
    (() => { throw new Error("currentLiquidationThreshold missing from getUserAccountData"); })();

  const ltv =
    pick<BigNumber>(data, "ltv", 4) ??
    (() => { throw new Error("ltv missing from getUserAccountData"); })();

  const healthFactor =
    pick<BigNumber>(data, "healthFactor", 5) ??
    (() => { throw new Error("healthFactor missing from getUserAccountData"); })();

  // Build result
  //const raw: GetPoolAaveDataRaw = {
  //  totalCollateralBase,
  //  totalDebtBase,
  //  availableBorrowsBase,
  //  currentLiquidationThreshold,
  //  ltv,
  //  healthFactor,
  //};
  const formatted: GetPoolAaveDataFormatted = {
    totalCollateralBase: fmt(totalCollateralBase, 8),        // base currency decimals (1e8)
    totalDebtBase: fmt(totalDebtBase, 8),
    availableBorrowsBase: fmt(availableBorrowsBase, 8),
    currentLiquidationThreshold: fmt(currentLiquidationThreshold, 4), // e.g. "0.78"
    ltv: fmt(ltv, 4),                                        // e.g. "0.73"
    healthFactor: fmt(healthFactor, 18),                     // ray → decimal
  };
  return { formatted };
}

export async function getAaveV3HealthFactor(
  userAddress: string,
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool or PoolAddressesProvider
): Promise<number> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );
  // Basic sanity: address must have code
  const code = await rpcProvider.getCode(contractAddress);
  if (code === "0x") {
    throw new Error(`No contract code at ${contractAddress}`);
  }
  // Try to resolve Pool via AddressesProvider.getPool(); if it reverts, assume
  // the given address IS the Pool already.
  let poolAddress = contractAddress;
  try {
    const addressesProvider = new ethers.Contract(
      contractAddress,
      IAddressesProviderAbi,
      rpcProvider
    );
    const resolved = await addressesProvider.getPool();
    if (resolved && ethers.utils.isAddress(resolved)) {
      poolAddress = resolved;
    }
  } catch {
    // ignore → treat contractAddress as the Pool
  }
  const pool = new ethers.Contract(poolAddress, IPoolAbi, rpcProvider);
  const data: any = await pool.getUserAccountData(userAddress);
  // v5 can return an array-like Result; named keys aren't guaranteed.
  const hfRay =
    (data && typeof data === "object" && "healthFactor" in data ? data.healthFactor : undefined) ??
    (Array.isArray(data) ? data[5] : data?.[5]);

  if (hfRay == null) {
    const keys = data && typeof data === "object" ? Object.keys(data) : [];
    throw new Error(`healthFactor missing from getUserAccountData result (keys: ${keys.join(",")})`);
  }
  const healthFactor = Number(ethers.utils.formatUnits(hfRay, 18));
  return healthFactor;
}

