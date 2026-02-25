// utils/AAVE.ts
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
const IPoolExtAbi = [
  // For getAll*, we need the reserves list
  "function getReservesList() view returns (address[])",
  // We use getReserveData(asset) to discover aToken / debt token addresses
  // ABI matches Aave v3 ReserveData shape enough to access address fields by index.
  "function getReserveData(address asset) view returns (tuple(tuple(uint256 data) configuration,uint128 liquidityIndex,uint128 currentLiquidityRate,uint128 variableBorrowIndex,uint128 currentVariableBorrowRate,uint128 currentStableBorrowRate,uint40 lastUpdateTimestamp,uint16 id,address aTokenAddress,address stableDebtTokenAddress,address variableDebtTokenAddress,address interestRateStrategyAddress,uint128 accruedToTreasury,uint128 unbackedMintCap,uint128 debtCeiling,uint16 debtCeilingDecimals,uint8 eModeCategoryId,uint16 liquidationProtocolFee,uint128 unbackedMinted,uint128 isolationModeTotalDebt,uint128 virtualAccruedToTreasury))",
];

const IERC20MinimalAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
];
const IPoolV3Abi = [
  "function getReserveData(address asset) view returns (\
    (uint256 configuration,\
     uint128 liquidityIndex,\
     uint128 currentLiquidityRate,\
     uint128 variableBorrowIndex,\
     uint128 currentVariableBorrowRate,\
     uint128 currentStableBorrowRate,\
     uint40 lastUpdateTimestamp,\
     uint16 id,\
     address aTokenAddress,\
     address stableDebtTokenAddress,\
     address variableDebtTokenAddress,\
     address interestRateStrategyAddress,\
     uint128 accruedToTreasury,\
     uint128 unbacked,\
     uint128 isolationModeTotalDebt))"
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

// ------------------------------ getSupplied ------------------------------
export async function getSupplied(
  userAddress: string,
  asset: string, // underlying token (e.g., USDC). We'll report balance keyed by this address.
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool OR PoolAddressesProvider
): Promise<Record<string, string>> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );

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
    // ignore
  }

  const pool = new ethers.Contract(poolAddress, IPoolV3Abi, rpcProvider);
  const reserveData: any = await pool.getReserveData(asset);
  const { aTokenAddress } = reserveData;
  if (!ethers.utils.isAddress(aTokenAddress) || aTokenAddress === ethers.constants.AddressZero) {
    throw new Error("aTokenAddress missing from getReserveData (reserve may be unlisted or ABI mismatch).");
  }
  const aToken = new ethers.Contract(aTokenAddress, IERC20MinimalAbi, rpcProvider);
  const underlying = new ethers.Contract(asset, IERC20MinimalAbi, rpcProvider);

  const [raw, decimals] = await Promise.all([
    aToken.balanceOf(userAddress),
    underlying.decimals(),
  ]);
  const suppliedAmount = ethers.utils.formatUnits(raw, decimals)
  return { suppliedAmount };
}

// ------------------------------ getBorrowed ------------------------------
export async function getBorrowed(
  userAddress: string,
  asset: string, // underlying token address; result keyed by this address
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool OR PoolAddressesProvider
): Promise<Record<string, string>> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );

  const code = await rpcProvider.getCode(contractAddress);
  if (code === "0x") {
    throw new Error(`No contract code at ${contractAddress}`);
  }

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
    // ignore
  }

  const pool = new ethers.Contract(poolAddress, IPoolV3Abi, rpcProvider);
  const reserveData: any = await pool.getReserveData(asset);

  const { stableDebtTokenAddress, variableDebtTokenAddress } = (await pool.getReserveData(asset));

  const stableDebt = new ethers.Contract(stableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
  const variableDebt = new ethers.Contract(variableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
  const underlying = new ethers.Contract(asset, IERC20MinimalAbi, rpcProvider);

  const [sBal, vBal, decimals] = await Promise.all([
    stableDebt.balanceOf(userAddress),
    variableDebt.balanceOf(userAddress),
    underlying.decimals(),
  ]);

  const total: BigNumber = BigNumber.from(sBal).add(vBal);
  const borrowedAmount =  ethers.utils.formatUnits(total, decimals)
  return { borrowedAmount };
}

// ------------------------------ getAllSupplied (if possible) ------------------------------
export async function getAllSupplied(
  userAddress: string,
  _asset: string, // unused; kept to match requested signature
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool OR PoolAddressesProvider
): Promise<Record<string, string>> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );

  const code = await rpcProvider.getCode(contractAddress);
  if (code === "0x") {
    throw new Error(`No contract code at ${contractAddress}`);
  }

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
    // ignore
  }

  const pool = new ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
  const reserves: string[] = await pool.getReservesList();

  const out: Record<string, string> = {};

  // Process reserves (sequential to be gentle on RPC; switch to Promise.all if desired)
  for (const reserve of reserves) {
    const reserveData: any = await pool.getReserveData(reserve);
    const aTokenAddress =
      pick<string>(reserveData, "aTokenAddress", 8) ??
      (() => {
        throw new Error("aTokenAddress missing from getReserveData");
      })();

    const aToken = new ethers.Contract(aTokenAddress, IERC20MinimalAbi, rpcProvider);
    const underlying = new ethers.Contract(reserve, IERC20MinimalAbi, rpcProvider);

    const [raw, decimals] = await Promise.all([
      aToken.balanceOf(userAddress),
      underlying.decimals(),
    ]);

    if (!raw.isZero()) {
      out[reserve] = ethers.utils.formatUnits(raw, decimals);
    }
  }

  return out;
}

// ------------------------------ getAllBorrowed (if possible) ------------------------------
export async function getAllBorrowed(
  userAddress: string,
  _asset: string, // unused; kept to match requested signature
  network: RpcNetwork,
  provider: string | null,
  providerApiKey: string | null,
  contractAddress: string // Pool OR PoolAddressesProvider
): Promise<Record<string, string>> {
  const rpcProvider = new ethers.providers.JsonRpcProvider(
    rpc(network, provider, providerApiKey)
  );

  const code = await rpcProvider.getCode(contractAddress);
  if (code === "0x") {
    throw new Error(`No contract code at ${contractAddress}`);
  }

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
    // ignore
  }

  const pool = new ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
  const reserves: string[] = await pool.getReservesList();

  const out: Record<string, string> = {};

  for (const reserve of reserves) {
    const reserveData: any = await pool.getReserveData(reserve);

    const stableDebtTokenAddress =
      pick<string>(reserveData, "stableDebtTokenAddress", 9) ??
      (() => {
        throw new Error("stableDebtTokenAddress missing from getReserveData");
      })();

    const variableDebtTokenAddress =
      pick<string>(reserveData, "variableDebtTokenAddress", 10) ??
      (() => {
        throw new Error("variableDebtTokenAddress missing from getReserveData");
      })();

    const stableDebt = new ethers.Contract(stableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
    const variableDebt = new ethers.Contract(variableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
    const underlying = new ethers.Contract(reserve, IERC20MinimalAbi, rpcProvider);

    const [sBal, vBal, decimals] = await Promise.all([
      stableDebt.balanceOf(userAddress),
      variableDebt.balanceOf(userAddress),
      underlying.decimals(),
    ]);

    const total: BigNumber = BigNumber.from(sBal).add(vBal);
    if (!total.isZero()) {
      out[reserve] = ethers.utils.formatUnits(total, decimals);
    }
  }

  return out;
}

