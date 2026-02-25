library(httr)
library(jsonlite)

# RPC endpoints - using more reliable ones
RPC_ENDPOINTS <- list(
  optimism = "https://mainnet.optimism.io",
  polygon = "https://polygon-rpc.com",
  arbitrum = "https://arb1.arbitrum.io/rpc",
  base = "https://base.llamarpc.com"  # More reliable Base RPC
)

# Make an eth_call to read from blockchain
ethCall <- function(to, data, rpc_url) {
  body <- list(
    jsonrpc = "2.0",
    method = "eth_call",
    params = list(
      list(to = to, data = data),
      "latest"
    ),
    id = 1
  )
  
  response <- POST(
    url = rpc_url,
    body = toJSON(body, auto_unbox = TRUE),
    add_headers("Content-Type" = "application/json"),
    timeout(10)
  )
  
  result <- content(response, as = "parsed", type = "application/json")
  
  if ("error" %in% names(result)) {
    return(list(success = FALSE, error = result$error$message))
  }
  
  return(list(success = TRUE, result = result$result))
}

# Check if contract exists at address
checkContractExists <- function(address, rpc_url) {
  body <- list(
    jsonrpc = "2.0",
    method = "eth_getCode",
    params = list(address, "latest"),
    id = 1
  )
  
  response <- POST(
    url = rpc_url,
    body = toJSON(body, auto_unbox = TRUE),
    add_headers("Content-Type" = "application/json")
  )
  
  result <- content(response, as = "parsed", type = "application/json")
  code <- result$result
  
  exists <- !is.null(code) && code != "0x"
  return(exists)
}

# Decode address from hex response
decodeAddress <- function(hex_data) {
  if (is.null(hex_data) || hex_data == "0x" || nchar(hex_data) < 42) {
    return(NULL)
  }
  address <- substr(hex_data, nchar(hex_data) - 39, nchar(hex_data))
  return(tolower(paste0("0x", address)))
}

# Try to find which chain the pool is on
findPoolChain <- function(pool_address) {
  cat("Searching for pool across all chains...\n")
  
  for (chain_name in names(RPC_ENDPOINTS)) {
    rpc_url <- RPC_ENDPOINTS[[chain_name]]
    cat("Checking", chain_name, "... ")
    
    tryCatch({
      exists <- checkContractExists(pool_address, rpc_url)
      if (exists) {
        cat("FOUND!\n")
        return(chain_name)
      } else {
        cat("not found\n")
      }
    }, error = function(e) {
      cat("error:", e$message, "\n")
    })
  }
  
  return(NULL)
}

# Get PoolManagerLogic address from PoolLogic contract
getPoolManagerLogicAddress <- function(pool_address, rpc_url) {
  cat("Step 1: Getting PoolManagerLogic address from PoolLogic...\n")
  
  # Call poolManagerLogic() on the pool
  result <- ethCall(
    to = pool_address,
    data = "0x3b1f8c9d",  # poolManagerLogic()
    rpc_url = rpc_url
  )
  
  if (!result$success) {
    cat("Failed to call poolManagerLogic():", result$error, "\n")
    return(NULL)
  }
  
  manager_logic_address <- decodeAddress(result$result)
  
  if (is.null(manager_logic_address) || manager_logic_address == "0x0000000000000000000000000000000000000000") {
    cat("PoolManagerLogic address is null or zero\n")
    return(NULL)
  }
  
  cat("✓ PoolManagerLogic address:", manager_logic_address, "\n")
  return(manager_logic_address)
}

# Get trader address from PoolManagerLogic contract
getTraderFromManagerLogic <- function(manager_logic_address, rpc_url) {
  cat("Step 2: Getting trader address from PoolManagerLogic...\n")
  
  # Call trader() on the PoolManagerLogic
  result <- ethCall(
    to = manager_logic_address,
    data = "0x6e94e2a9",  # trader()
    rpc_url = rpc_url
  )
  
  if (!result$success) {
    cat("Failed to call trader():", result$error, "\n")
    return(NULL)
  }
  
  trader_address <- decodeAddress(result$result)
  
  if (is.null(trader_address) || trader_address == "0x0000000000000000000000000000000000000000") {
    cat("Trader address is null or zero\n")
    return(NULL)
  }
  
  cat("✓ Trader address:", trader_address, "\n")
  return(trader_address)
}

# Main function with auto chain detection
getPoolTraderOnchain <- function(pool_address, chain = NULL) {
  # Normalize address
  pool_address <- tolower(pool_address)
  if (!grepl("^0x", pool_address)) {
    pool_address <- paste0("0x", pool_address)
  }
  
  cat("\n=== Fetching trader for pool:", pool_address, "===\n")
  
  # If chain not specified, try to find it
  if (is.null(chain)) {
    cat("Chain not specified, searching...\n")
    chain <- findPoolChain(pool_address)
    if (is.null(chain)) {
      cat("✗ Pool not found on any supported chain\n")
      return(NULL)
    }
  } else {
    # Verify pool exists on specified chain
    rpc_url <- RPC_ENDPOINTS[[chain]]
    exists <- checkContractExists(pool_address, rpc_url)
    if (!exists) {
      cat("✗ Pool does not exist on", chain, "\n")
      cat("Searching other chains...\n")
      chain <- findPoolChain(pool_address)
      if (is.null(chain)) {
        cat("✗ Pool not found on any supported chain\n")
        return(NULL)
      }
    }
  }
  
  cat("Using chain:", chain, "\n\n")
  
  # Get RPC endpoint
  rpc_url <- RPC_ENDPOINTS[[chain]]
  
  # Step 1: Get PoolManagerLogic address
  manager_logic_address <- getPoolManagerLogicAddress(pool_address, rpc_url)
  if (is.null(manager_logic_address)) {
    return(NULL)
  }
  
  # Step 2: Get trader address from PoolManagerLogic
  trader_address <- getTraderFromManagerLogic(manager_logic_address, rpc_url)
  
  return(trader_address)
}

# Main wrapper function
getPoolTrader <- function(protocol, pool, chain = NULL) {
  if (protocol == "dhedge") {
    return(getPoolTraderOnchain(pool, chain))
  }
  return(NULL)
}

# Test - let it auto-detect the chain
cat("\n========================================\n")
cat("Testing with cbBTC Trading Bot\n")
cat("========================================\n")

# First try with auto-detection (no chain specified)
trader <- getPoolTrader("dhedge", "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d", chain = NULL)

if (!is.null(trader)) {
  cat("\n✓✓✓ SUCCESS ✓✓✓\n")
  cat("Trader address:", trader, "\n")
} else {
  cat("\n✗✗✗ FAILED ✗✗✗\n")
}
