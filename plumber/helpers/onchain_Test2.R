library(httr)
library(jsonlite)

# RPC endpoints for different chains
RPC_ENDPOINTS <- list(
  optimism = "https://mainnet.optimism.io",
  polygon = "https://polygon-rpc.com",
  arbitrum = "https://arb1.arbitrum.io/rpc",
  base = "https://mainnet.base.org"
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
  # Extract last 40 characters (20 bytes = Ethereum address)
  address <- substr(hex_data, nchar(hex_data) - 39, nchar(hex_data))
  return(tolower(paste0("0x", address)))
}

# Function selectors for different manager-related functions
FUNCTION_SELECTORS <- list(
  manager = "0x481c6a75",                    # manager()
  managerLogic = "0xb5b3ddfa",               # managerLogic()
  poolManagerLogic = "0x3b1f8c9d",           # poolManagerLogic()
  trader = "0x6e94e2a9",                     # trader()
  owner = "0x8da5cb5b"                       # owner()
)

# Get trader address directly from blockchain - tries multiple functions
getPoolTraderOnchain <- function(pool_address, chain = "optimism") {
  # Normalize address
  pool_address <- tolower(pool_address)
  if (!grepl("^0x", pool_address)) {
    pool_address <- paste0("0x", pool_address)
  }
  
  cat("Attempting to fetch trader for pool:", pool_address, "on chain:", chain, "\n")
  
  # Get RPC endpoint
  rpc_url <- RPC_ENDPOINTS[[chain]]
  if (is.null(rpc_url)) {
    cat("Unsupported chain:", chain, "\n")
    return(NULL)
  }
  
  # Try each function selector
  for (func_name in names(FUNCTION_SELECTORS)) {
    selector <- FUNCTION_SELECTORS[[func_name]]
    cat("Trying function:", func_name, "(", selector, ")... ")
    
    result <- ethCall(to = pool_address, data = selector, rpc_url = rpc_url)
    
    if (result$success) {
      trader_address <- decodeAddress(result$result)
      
      if (!is.null(trader_address) && trader_address != "0x0000000000000000000000000000000000000000") {
        cat("SUCCESS!\n")
        cat("Trader address:", trader_address, "\n")
        return(trader_address)
      } else {
        cat("returned null address\n")
      }
    } else {
      cat("failed -", result$error, "\n")
    }
  }
  
  cat("\nAll attempts failed. This might not be a valid dHEDGE pool contract.\n")
  return(NULL)
}

# Main function
getPoolTrader <- function(protocol, pool, chain = "optimism") {
  if (protocol == "dhedge") {
    return(getPoolTraderOnchain(pool, chain))
  }
  return(NULL)
}

# Test with a known dHEDGE pool
# Example: cbBTC Trading Bot on Base
trader <- getPoolTrader("dhedge", "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d", "base")

if (!is.null(trader)) {
  cat("\n✓ Successfully retrieved trader address:", trader, "\n")
} else {
  cat("\n✗ Failed to retrieve trader address\n")
}
