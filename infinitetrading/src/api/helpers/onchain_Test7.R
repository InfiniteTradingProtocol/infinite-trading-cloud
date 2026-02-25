library(httr)
library(jsonlite)

# RPC endpoints for all supported chains
RPC_ENDPOINTS <- list(
  optimism = "https://mainnet.optimism.io",
  polygon = "https://polygon-rpc.com",
  arbitrum = "https://arb1.arbitrum.io/rpc",
  base = "https://base.llamarpc.com"
)

# Make an eth_call to blockchain
ethCall <- function(to, data, rpc_url) {
  body <- list(
    jsonrpc = "2.0",
    method = "eth_call",
    params = list(list(to = to, data = data), "latest"),
    id = 1
  )
  
  response <- POST(
    url = rpc_url,
    body = toJSON(body, auto_unbox = TRUE),
    add_headers("Content-Type" = "application/json")
  )
  
  result <- content(response, as = "parsed", type = "application/json")
  
  if ("error" %in% names(result)) {
    return(list(success = FALSE, error = result$error$message))
  }
  
  return(list(success = TRUE, result = result$result))
}

# Decode address from hex response
decodeAddress <- function(hex_data) {
  if (is.null(hex_data) || hex_data == "0x" || nchar(hex_data) < 42) {
    return(NULL)
  }
  address <- substr(hex_data, nchar(hex_data) - 39, nchar(hex_data))
  return(tolower(paste0("0x", address)))
}

# Function selectors (calculated from keccak256 hash)
# poolManagerLogic() = 0x3b1f8c9d
# trader() = 0x6e94e2a9

# Main function to get trader address
getPoolTrader <- function(vault, network) {
  # Normalize inputs
  vault <- tolower(vault)
  if (!grepl("^0x", vault)) {
    vault <- paste0("0x", vault)
  }
  
  network <- tolower(network)
  
  # Get RPC URL for network
  rpc_url <- RPC_ENDPOINTS[[network]]
  if (is.null(rpc_url)) {
    cat("Error: Unsupported network:", network, "\n")
    cat("Supported networks:", paste(names(RPC_ENDPOINTS), collapse = ", "), "\n")
    return(NULL)
  }
  
  cat("Getting trader for vault:", vault, "on", network, "\n")
  
  # Step 1: Call poolManagerLogic() on the vault to get PoolManagerLogic address
  cat("Step 1: Calling poolManagerLogic()...\n")
  result1 <- ethCall(vault, "0x3b1f8c9d", rpc_url)
  
  if (!result1$success) {
    cat("Error calling poolManagerLogic():", result1$error, "\n")
    return(NULL)
  }
  
  pool_manager_address <- decodeAddress(result1$result)
  
  if (is.null(pool_manager_address) || pool_manager_address == "0x0000000000000000000000000000000000000000") {
    cat("Error: poolManagerLogic returned null or zero address\n")
    return(NULL)
  }
  
  cat("PoolManagerLogic address:", pool_manager_address, "\n")
  
  # Step 2: Call trader() on the PoolManagerLogic contract
  cat("Step 2: Calling trader() on PoolManagerLogic...\n")
  result2 <- ethCall(pool_manager_address, "0x6e94e2a9", rpc_url)
  
  if (!result2$success) {
    cat("Error calling trader():", result2$error, "\n")
    return(NULL)
  }
  
  trader_address <- decodeAddress(result2$result)
  
  if (is.null(trader_address) || trader_address == "0x0000000000000000000000000000000000000000") {
    cat("Error: trader() returned null or zero address\n")
    return(NULL)
  }
  
  cat("✓ Trader address:", trader_address, "\n")
  return(trader_address)
}

# Test cases
cat("\n" , rep("=", 60), "\n", sep = "")
cat("TEST 1: cbBTC Trading Bot on Base\n")
cat(rep("=", 60), "\n\n", sep = "")

trader1 <- getPoolTrader(
  vault = "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d",
  network = "base"
)

if (!is.null(trader1)) {
  expected1 <- "0x8893ca7295dfb55260ee0db7faa03ac8dcd8f5f5"
  if (tolower(trader1) == tolower(expected1)) {
    cat("\n✓✓✓ SUCCESS - Correct trader address!\n")
  } else {
    cat("\n✗ Got:", trader1, "\n")
    cat("Expected:", expected1, "\n")
  }
} else {
  cat("\n✗✗✗ FAILED\n")
}

# You can add more test cases here if needed
# trader2 <- getPoolTrader(vault = "0x...", network = "optimism")
