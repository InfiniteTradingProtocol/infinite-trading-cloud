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

# All possible function selectors to try
FUNCTION_ATTEMPTS <- list(
  # Manager-related functions
  list(name = "manager()", selector = "0x481c6a75", type = "direct"),
  list(name = "poolManagerLogic()", selector = "0x3b1f8c9d", type = "indirect"),
  list(name = "getManager()", selector = "0xd5009584", type = "direct"),
  list(name = "managerLogic()", selector = "0xb5b3ddfa", type = "direct"),
  list(name = "trader()", selector = "0x6e94e2a9", type = "direct"),
  list(name = "owner()", selector = "0x8da5cb5b", type = "direct"),
  
  # Factory query functions (might return trader directly)
  list(name = "creator()", selector = "0x02d05d3f", type = "direct"),
  list(name = "fundCreator()", selector = "0x4b2f336d", type = "direct")
)

# Try all possible ways to get trader
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
  
  # Try each function
  for (attempt in FUNCTION_ATTEMPTS) {
    cat("Trying:", attempt$name, "...\n")
    
    if (attempt$type == "direct") {
      # Direct call - should return trader address
      result <- ethCall(pool_address, attempt$selector, rpc_url)
      
      if (result$success) {
        trader <- decodeAddress(result$result)
        if (!is.null(trader) && trader != "0x0000000000000000000000000000000000000000") {
          cat("✓ SUCCESS! Found trader via", attempt$name, "\n")
          cat("Trader address:", trader, "\n")
          return(trader)
        } else {
          cat("  → Returned null/zero address\n")
        }
      } else {
        cat("  → Failed:", result$error, "\n")
      }
      
    } else if (attempt$type == "indirect") {
      # Indirect - returns another contract address to query
      result <- ethCall(pool_address, attempt$selector, rpc_url)
      
      if (result$success) {
        intermediate_address <- decodeAddress(result$result)
        if (!is.null(intermediate_address) && intermediate_address != "0x0000000000000000000000000000000000000000") {
          cat("  → Got intermediate contract:", intermediate_address, "\n")
          cat("  → Calling trader() on intermediate...\n")
          
          # Now try to get trader from intermediate contract
          trader_result <- ethCall(intermediate_address, "0x6e94e2a9", rpc_url)  # trader()
          
          if (trader_result$success) {
            trader <- decodeAddress(trader_result$result)
            if (!is.null(trader) && trader != "0x0000000000000000000000000000000000000000") {
              cat("✓ SUCCESS! Found trader via", attempt$name, "+ trader()\n")
              cat("Trader address:", trader, "\n")
              return(trader)
            }
          } else {
            cat("  → trader() call failed:", trader_result$error, "\n")
          }
        }
      } else {
        cat("  → Failed:", result$error, "\n")
      }
    }
  }
  
  cat("\n✗ All attempts failed\n")
  cat("\nDEBUG: Let's check the GraphQL API to see what it returns...\n")
  
  # As a last resort, show what GraphQL would return
  tryCatch({
    gql_query <- sprintf('query allFundsByAddresses { allFundsByAddresses(addresses: "%s") { traderAddress poolManagerLogicAddress managerLogicAddress } }', pool_address)
    gql_body <- list(query = gql_query)
    gql_response <- POST(
      url = "https://api-v2.dhedge.org/graphql",
      body = gql_body,
      encode = "json"
    )
    gql_result <- content(gql_response, as = "parsed", type = "application/json")
    
    if ("data" %in% names(gql_result) && length(gql_result$data$allFundsByAddresses) > 0) {
      fund_data <- gql_result$data$allFundsByAddresses[[1]]
      cat("\nGraphQL API returned:\n")
      cat("  traderAddress:", fund_data$traderAddress, "\n")
      cat("  poolManagerLogicAddress:", fund_data$poolManagerLogicAddress, "\n")
      cat("  managerLogicAddress:", fund_data$managerLogicAddress, "\n")
      
      # Try using the poolManagerLogicAddress from GraphQL
      if (!is.null(fund_data$poolManagerLogicAddress)) {
        cat("\nTrying trader() on poolManagerLogicAddress from GraphQL...\n")
        trader_result <- ethCall(fund_data$poolManagerLogicAddress, "0x6e94e2a9", rpc_url)
        if (trader_result$success) {
          trader <- decodeAddress(trader_result$result)
          if (!is.null(trader) && trader != "0x0000000000000000000000000000000000000000") {
            cat("✓ SUCCESS using GraphQL intermediate address!\n")
            return(trader)
          }
        }
      }
      
      return(fund_data$traderAddress)
    }
  }, error = function(e) {
    cat("GraphQL query failed:", e$message, "\n")
  })
  
  return(NULL)
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
  cat("Final trader address:", trader, "\n")
} else {
  cat("\n✗✗✗ FAILED ✗✗✗\n")
}
