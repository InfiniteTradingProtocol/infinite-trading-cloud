library(httr)
library(jsonlite)

# RPC endpoints
RPC_ENDPOINTS <- list(
  optimism = "https://mainnet.optimism.io",
  polygon = "https://polygon-rpc.com",
  arbitrum = "https://arb1.arbitrum.io/rpc",
  base = "https://base.llamarpc.com"
)

# Make an eth_call
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

# Decode address from hex
decodeAddress <- function(hex_data) {
  if (is.null(hex_data) || hex_data == "0x" || nchar(hex_data) < 42) {
    return(NULL)
  }
  address <- substr(hex_data, nchar(hex_data) - 39, nchar(hex_data))
  return(tolower(paste0("0x", address)))
}

# Get trader from GraphQL (for validation/comparison)
getTraderFromGraphQL <- function(pool_address) {
  gql_query <- sprintf('query allFundsByAddresses { allFundsByAddresses(addresses: "%s") { traderAddress poolManagerLogicAddress managerLogicAddress } }', pool_address)
  gql_body <- list(query = gql_query)
  
  response <- POST(
    url = "https://api-v2.dhedge.org/graphql",
    body = gql_body,
    encode = "json"
  )
  
  result <- content(response, as = "parsed", type = "application/json")
  
  if ("data" %in% names(result) && length(result$data$allFundsByAddresses) > 0) {
    return(result$data$allFundsByAddresses[[1]])
  }
  
  return(NULL)
}

# Main function - uses GraphQL to get intermediate contract, then queries onchain
getPoolTraderOnchain <- function(pool_address, chain = "base") {
  pool_address <- tolower(pool_address)
  if (!grepl("^0x", pool_address)) {
    pool_address <- paste0("0x", pool_address)
  }
  
  cat("\n=== Fetching trader for pool:", pool_address, "===\n")
  cat("Chain:", chain, "\n\n")
  
  rpc_url <- RPC_ENDPOINTS[[chain]]
  if (is.null(rpc_url)) {
    cat("Unsupported chain\n")
    return(NULL)
  }
  
  # Step 1: Query GraphQL to get the structure
  cat("Step 1: Querying GraphQL API for pool structure...\n")
  gql_data <- getTraderFromGraphQL(pool_address)
  
  if (is.null(gql_data)) {
    cat("✗ GraphQL query failed\n")
    return(NULL)
  }
  
  cat("GraphQL returned:\n")
  cat("  traderAddress:", gql_data$traderAddress, "\n")
  cat("  poolManagerLogicAddress:", gql_data$poolManagerLogicAddress, "\n")
  if (!is.null(gql_data$managerLogicAddress)) {
    cat("  managerLogicAddress:", gql_data$managerLogicAddress, "\n")
  }
  
  # Step 2: Verify trader address onchain
  if (!is.null(gql_data$poolManagerLogicAddress)) {
    cat("\nStep 2: Verifying trader onchain via poolManagerLogic...\n")
    
    # Call trader() on the poolManagerLogic contract
    result <- ethCall(
      to = gql_data$poolManagerLogicAddress,
      data = "0x6e94e2a9",  # trader()
      rpc_url = rpc_url
    )
    
    if (result$success) {
      trader_onchain <- decodeAddress(result$result)
      if (!is.null(trader_onchain) && trader_onchain != "0x0000000000000000000000000000000000000000") {
        cat("✓ Verified trader onchain:", trader_onchain, "\n")
        
        # Compare with GraphQL result
        if (tolower(trader_onchain) == tolower(gql_data$traderAddress)) {
          cat("✓ Matches GraphQL result\n")
        } else {
          cat("⚠ WARNING: Onchain trader differs from GraphQL!\n")
          cat("  GraphQL:", gql_data$traderAddress, "\n")
          cat("  Onchain:", trader_onchain, "\n")
        }
        
        return(trader_onchain)
      }
    } else {
      cat("✗ Failed to call trader() onchain:", result$error, "\n")
      cat("Using GraphQL result as fallback\n")
    }
  }
  
  # Fallback: use GraphQL result
  return(gql_data$traderAddress)
}

# Main wrapper
getPoolTrader <- function(protocol, pool, chain = "base") {
  if (protocol == "dhedge") {
    return(getPoolTraderOnchain(pool, chain))
  }
  return(NULL)
}

# Test
cat("\n========================================\n")
cat("Testing with cbBTC Trading Bot on Base\n")
cat("========================================\n")

trader <- getPoolTrader("dhedge", "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d", "base")

if (!is.null(trader)) {
  cat("\n✓✓✓ SUCCESS ✓✓✓\n")
  cat("Trader address:", trader, "\n")
  
  # Verify it's the expected address
  expected <- "0x8893ca7295dfb55260ee0db7faa03ac8dcd8f5f5"
  if (tolower(trader) == tolower(expected)) {
    cat("✓ Correct! Matches expected trader address\n")
  } else {
    cat("✗ WARNING: Does not match expected address\n")
    cat("  Expected:", expected, "\n")
    cat("  Got:", trader, "\n")
  }
} else {
  cat("\n✗✗✗ FAILED ✗✗✗\n")
}
