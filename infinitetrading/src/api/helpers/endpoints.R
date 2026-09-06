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
  "lend",
  "unlend",
  "borrow",
  "repay",
  "getPoolAaveData",
  "getHealthFactor",
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
  # gateway/deploy.sh emits an nginx route for it (it was otherwise 404ing
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
