require(httr); require(jsonlite); require(dotenv)
load_dot_env("~/infinitetrading/src/api/.env")

# Network RPC endpoints
rpc_endpoints <- list(
  ethereum = paste0("https://eth-mainnet.g.alchemy.com/v2/", Sys.getenv("ALCHEMY_BALANCES_APIKEY")),
  polygon  = paste0("https://polygon-mainnet.g.alchemy.com/v2/", Sys.getenv("ALCHEMY_BALANCES_APIKEY")),
  optimism = paste0("https://opt-mainnet.g.alchemy.com/v2/", Sys.getenv("ALCHEMY_BALANCES_APIKEY")),
  arbitrum = paste0("https://arb-mainnet.g.alchemy.com/v2/", Sys.getenv("ALCHEMY_BALANCES_APIKEY")),
  base     = paste0("https://base-mainnet.g.alchemy.com/v2/", Sys.getenv("ALCHEMY_BALANCES_APIKEY"))
)

networks = c("ethereum","polygon","base","arbitrum","optimism")

# Get ETH balance via direct RPC call
get_balance_rpc <- function(address, rpc_url) {
  # Ensure address has 0x prefix and is properly formatted
  address <- as.character(address)
  address <- trimws(address)
  if (!grepl("^0x", address)) {
    address <- paste0("0x", address)
  }
  
  payload <- list(
    jsonrpc = "2.0",
    method = "eth_getBalance",
    params = list(address, "latest"),
    id = 1
  )
  
  response <- tryCatch({
    POST(
      url = rpc_url,
      body = toJSON(payload, auto_unbox = TRUE),
      content_type("application/json"),
      encode = "json"
    )
  }, error = function(e) {
    cat("Error making RPC call for", address, ":", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(response)) {
    return(NA)
  }
  
  if (status_code(response) != 200) {
    cat("Error: RPC call failed with status", status_code(response), "for", address, "\n")
    return(NA)
  }
  
  result <- tryCatch({
    fromJSON(content(response, "text", encoding = "UTF-8"))
  }, error = function(e) {
    cat("Error parsing JSON response for", address, ":", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(result)) {
    return(NA)
  }
  
  if (!is.null(result$error)) {
    cat("RPC Error for", address, ":", result$error$message, "\n")
    return(NA)
  }
  
  # Convert hex balance to decimal ETH
  balance_hex <- gsub("^0x", "", result$result)
  if (balance_hex == "" || is.null(balance_hex)) {
    return(0)
  }
  
  balance_wei <- tryCatch({
    strtoi(balance_hex, base = 16L)
  }, error = function(e) {
    cat("Error converting hex balance for", address, ":", e$message, "\n")
    return(NA)
  })
  
  if (is.na(balance_wei)) {
    return(NA)
  }
  
  balance_eth <- balance_wei / 1e18
  return(balance_eth)
}

# Main function to get gas balances
getGasBalances <- function(addresses, network, structured = FALSE) {
  max_batch_size <- 20
  sleep_interval <- 0.2  # 200ms between batches (5 requests/sec)
  
  get_single_network_balances <- function(addresses, net) {
    rpc_url <- rpc_endpoints[[net]]
    
    if (is.null(rpc_url)) {
      cat("Error: No RPC endpoint configured for", net, "\n")
      return(if (structured) list() else numeric(0))
    }
    
    address_batches <- split(addresses, ceiling(seq_along(addresses) / max_batch_size))
    balances <- c()
    structured_list <- list()
    initial <- TRUE
    
    for (batch in address_batches) {
      if (!initial) Sys.sleep(sleep_interval)
      initial <- FALSE
      
      for (address in batch) {
        bal <- get_balance_rpc(address, rpc_url)
        balances <- c(balances, bal)
        
        if (structured) {
          structured_list[[length(structured_list) + 1]] <- list(
            network = net,
            wallet = address,
            balance = bal
          )
        }
      }
    }
    
    if (structured) return(structured_list)
    else return(as.numeric(balances))
  }
  
  if (network == "all") {
    if (!structured) stop("Use structured = TRUE when querying multiple networks.")
    results <- list()
    for (net in networks) {
      cat("Fetching balances for", net, "...\n")
      results <- append(results, get_single_network_balances(addresses, net))
    }
    return(results)
  } else {
    return(get_single_network_balances(addresses, network))
  }
}

# For backwards compatibility
max_batch_size = 20
sleep_interval = 0.2

cat("Gas balance monitor initialized with RPC endpoints\n")
