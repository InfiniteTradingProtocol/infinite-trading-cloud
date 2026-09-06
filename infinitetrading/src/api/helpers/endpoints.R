# Define the vector of endpoints
endpoints <- c(
  "createGasWallet",
  "getNewApiKey",
  "linkGasWallet",
  "unlinkGasWallet",
  "approve",
  "setBot",
  "deleteBot",
  "vaultTrade",
  # NOTE: the top-level "lend", "unlend", "borrow", "repay",
  # "getPoolAaveData" and "getHealthFactor" endpoints were removed. They were
  # Aave-v3-only despite their generic names, and duplicated the per-protocol
  # routes. Use /aaveV3/lend, /aaveV3/unlend, /aaveV3/borrow, /aaveV3/repay,
  # /aaveV3/getPoolData and /aaveV3/getHealthFactor instead; the "aaveV3"
  # entry below covers all of them.
  "getGasBalance",
  "getCandles",
  "getTicks",
  "getContract",
  "getSymbol",
  "poolComposition",
  "aaveV3",
  "compoundV3",
  "fluid",
  "getTotalYield",
  "getEstimatedAnualYield",
  "getAllYields",
  "getGasWalletPools",
  "associateGasWallet",
  "deassociateGasWallet",
  "getAssociatedGasWallets",
  "getAllGasBalance",
  "getAllBots",
  "getAllCEXSubaccounts",
  "mintManagerFee",
  # Express-only endpoint (src/requests/mintManagerFeeBatch.ts). It has no R
  # implementation and never had one; it is listed here solely so
  # ops/nginx/generate-endpoints-conf.sh emits an nginx route for it (it was otherwise 404ing
  # publicly despite working on port 8000).
  "mintManagerFeeBatch",
  # Express-only (src/requests/mintAllFeesByManager.ts). Same batching as
  # mintManagerFeeBatch, but discovers the pools from a manager address
  # instead of taking a comma-separated list.
  "mintAllFeesByManager",
  "registerCEXSubaccount",
  "setCEXSide",
  "getCEXSide",
  "setCEXStrategy",
  "deleteCEXBot",
  "deactivateCEXBot",
  "deleteCEXSubaccount",
  "getAllCEXSubaccounts",
  "llmIntrospect",
  "addLiquidity",
  "removeLiquidity"
)
hidden_endpoints <- c("/createGasWallet","/linkGasWallet","/unlinkGasWallet","/getAllBots","/getAllGasBalance","/getEstimatedAnualYield", "/getTotalYield","/getAllYields","/getGasWalletPools","/associateGasWallet","/deassociateGasWallet","/getAssociatedGasWallets","/getAllCEXSubaccounts","/setCEXStrategy")
