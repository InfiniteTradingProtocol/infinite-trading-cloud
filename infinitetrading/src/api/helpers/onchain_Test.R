library(httr)
library(jsonlite)

# RPC endpoints for different chains where dHEDGE operates
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
    cat("RPC Error:", result$error$message, "\n")
    return(NULL)
  }
  
  return(result$result)
}

# Encode the manager() function call
# Function selector: keccak256("manager()") = 0x481c6a75
encodeManagerCall <- function() {
  return("0x481c6a75")
}

# Decode address from hex response
decodeAddress <- function(hex_data) {
  if (is.null(hex_data) || hex_data == "0x") {
    return(NULL)
  }
  # Extract last 40 characters (20 bytes = Ethereum address)
  address <- substr(hex_data, nchar(hex_data) - 39, nchar(hex_data))
  return(paste0("0x", address))
}

# Get trader address directly from blockchain
getPoolTraderOnchain <- function(pool_address, chain = "optimism") {
  # Normalize address
  if (!grepl("^0x", pool_address)) {
    pool_address <- paste0("0x", pool_address)
  }
  
  # Get RPC endpoint
  rpc_url <- RPC_ENDPOINTS[[chain]]
  if (is.null(rpc_url)) {
    cat("Unsupported chain:", chain, "\n")
    return(NULL)
  }
  
  # Encode the manager() function call
  data <- encodeManagerCall()
  
  # Make the eth_call to the pool contract
  result <- ethCall(to = pool_address, data = data, rpc_url = rpc_url)
  
  if (is.null(result)) {
    cat("Failed to fetch trader address from blockchain\n")
    return(NULL)
  }
  
  # Decode the address
  trader_address <- decodeAddress(result)
  
  if (!is.null(trader_address)) {
    cat("Trader address for pool", pool_address, ":", trader_address, "\n")
  }
  
  return(trader_address)
}

# Main function - updated to use onchain method
getPoolTrader <- function(protocol, pool, chain = "optimism") {
  if (protocol == "dhedge") {
    return(getPoolTraderOnchain(pool, chain))
  }
  return(NULL)
}

# Example usage:
trader <- getPoolTrader("dhedge", "0x9b1a83432996e4e075dd24d4ed7288a2c4ca730a", "optimism")

# trader <- getPoolTrader("dhedge", "0xYourPoolAddress", "")
