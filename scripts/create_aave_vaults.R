#!/usr/bin/env Rscript
# Create vaults for AAVE-optimized crossover strategies
# This script creates 6 new vaults (one per strategy pair)

# Get workspace root
if (interactive()) {
  workspace_root <- getwd()
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- sub("--file=", "", file_arg)
    workspace_root <- normalizePath(file.path(dirname(script_path), ".."))
  } else {
    workspace_root <- getwd()
  }
}

source(file.path(workspace_root, "infinitetrading/src/api/api.R"))

# API Key for vault creation
apiKey <- Sys.getenv("ITP_API_KEY")
if (apiKey == "") {
  apiKey <- "da586db798b805914362612017ceda607bbcb592915b60c118a06382535160b5cea57c19cc5af319ac33d2e41bf9d34522ffea91e68995e8ce0f35fd27ad24ea"
}

# Get gas wallet address from API
gas_wallet_result <- itp_api(
  endpoint = "getGasWallet",
  params = list(apiKey = apiKey)
)
gas_wallet <- gas_wallet_result$msg
cat(sprintf("✓ Gas wallet: %s\n\n", gas_wallet))

# Strategy configurations
strategies <- list(
  list(
    network = "base",
    pair = "MORPHO-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP MORPHO/USDC EMA Crossover + AAVE",
    symbol = "ITPMOR",
    supportedAssets = list(
      list(asset = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"), # USDC
      list(asset = "0x47c031236e19d024b42f8AE6780E44A573170703")  # MORPHO
    ),
    fee = "200" # 2%
  ),
  list(
    network = "optimism",
    pair = "SNX-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP SNX/USDC EMA Crossover + AAVE",
    symbol = "ITPSNX",
    supportedAssets = list(
      list(asset = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"), # USDC
      list(asset = "0x8700dAec35aF8Ff88c16BdF0418774CB3D7599B4")  # SNX
    ),
    fee = "200"
  ),
  list(
    network = "base",
    pair = "AERO-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP AERO/USDC EMA Crossover + AAVE",
    symbol = "ITPAERO",
    supportedAssets = list(
      list(asset = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"), # USDC
      list(asset = "0x940181a94A35A4569E4529A3CDfB74e38FD98631")  # AERO
    ),
    fee = "200"
  ),
  list(
    network = "optimism",
    pair = "AAVE-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP AAVE/USDC EMA Crossover + AAVE",
    symbol = "ITPAAVE",
    supportedAssets = list(
      list(asset = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"), # USDC
      list(asset = "0x76FB31fb4af56892A25e32cFC43De717950c9278")  # AAVE
    ),
    fee = "200"
  ),
  list(
    network = "base",
    pair = "cbBTC-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP cbBTC/USDC EMA Crossover + AAVE",
    symbol = "ITPCBTC",
    supportedAssets = list(
      list(asset = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"), # USDC
      list(asset = "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf")  # cbBTC
    ),
    fee = "200"
  ),
  list(
    network = "optimism",
    pair = "WETH-USDC",
    managerName = "Infinite Trading Bot",
    poolName = "ITP WETH/USDC EMA Crossover + AAVE",
    symbol = "ITPWETH",
    supportedAssets = list(
      list(asset = "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"), # USDC
      list(asset = "0x4200000000000000000000000000000000000006")  # WETH
    ),
    fee = "200"
  )
)

# Create vaults
vault_addresses <- character(length(strategies))
names(vault_addresses) <- sapply(strategies, function(s) s$pair)

cat("=" %R% 80, "\n")
cat("CREATING AAVE-OPTIMIZED VAULTS\n")
cat("=" %R% 80, "\n\n")

for (i in seq_along(strategies)) {
  strat <- strategies[[i]]
  
  cat(sprintf("[%d/%d] Creating vault for %s on %s...\n", i, length(strategies), strat$pair, strat$network))
  
  tryCatch({
    # Create pool/vault
    result <- itp_api(
      endpoint = "createPool",
      params = list(
        apiKey = apiKey,
        network = strat$network,
        managerName = strat$managerName,
        poolName = strat$poolName,
        symbol = strat$symbol,
        supportedAssets = strat$supportedAssets,
        fee = strat$fee
      )
    )
    
    if (result$status == "success") {
      vault_address <- result$msg
      vault_addresses[strat$pair] <- vault_address
      cat(sprintf("  ✓ Vault created: %s\n", vault_address))
      
      # Wait for transaction to confirm
      Sys.sleep(10)
      
      # Set gas wallet as trader
      cat(sprintf("  → Setting trader to %s...\n", gas_wallet))
      trader_result <- itp_api(
        endpoint = "setTrader",
        params = list(
          apiKey = apiKey,
          network = strat$network,
          pool = vault_address,
          traderAccount = gas_wallet
        )
      )
      
      if (trader_result$status == "success") {
        cat(sprintf("  ✓ Trader set successfully\n"))
      } else {
        cat(sprintf("  ✗ Failed to set trader: %s\n", trader_result$msg))
      }
      
      # Wait before next vault
      Sys.sleep(5)
      
    } else {
      cat(sprintf("  ✗ Failed to create vault: %s\n", result$msg))
    }
    
  }, error = function(e) {
    cat(sprintf("  ✗ Error: %s\n", e$message))
  })
  
  cat("\n")
}

# Print summary
cat("=" %R% 80, "\n")
cat("VAULT CREATION SUMMARY\n")
cat("=" %R% 80, "\n\n")

for (pair in names(vault_addresses)) {
  if (vault_addresses[pair] != "") {
    cat(sprintf("%-15s  %s\n", pair, vault_addresses[pair]))
  } else {
    cat(sprintf("%-15s  FAILED\n", pair))
  }
}

# Save to file for use in strategy
output_file <- file.path(workspace_root, "infinitetrading/src/strategies/aave_vault_addresses.R")
cat("\n\nSaving vault addresses to", output_file, "...\n")

vault_code <- sprintf('# AAVE-Optimized Vault Addresses
# Generated on %s

AAVE_VAULT_ADDRESSES <- list(
  "MORPHO-USDC" = "%s",
  "SNX-USDC" = "%s",
  "AERO-USDC" = "%s",
  "AAVE-USDC" = "%s",
  "cbBTC-USDC" = "%s",
  "WETH-USDC" = "%s"
)
',
  Sys.time(),
  vault_addresses["MORPHO-USDC"],
  vault_addresses["SNX-USDC"],
  vault_addresses["AERO-USDC"],
  vault_addresses["AAVE-USDC"],
  vault_addresses["cbBTC-USDC"],
  vault_addresses["WETH-USDC"]
)

writeLines(vault_code, output_file)
cat("✓ Vault addresses saved!\n\n")

cat("Next steps:\n")
cat("1. Fund the vaults with initial USDC\n")
cat("2. Run crossOversAndAAVE.R strategy\n")
cat("3. Monitor PM2 logs: pm2 logs strategy-crossovers-aave\n\n")
