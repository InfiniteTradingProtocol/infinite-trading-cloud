# Batched pool composition fetching using multicall endpoint
# Handles any number of pools by splitting into batches of 50

require(httr)
require(jsonlite)

BATCH_SIZE <- 50  # Max pools per batch (set in endpoint)
API_ENDPOINT <- "http://localhost:8000/poolCompositionBatch"

# Fetch compositions for multiple pools in batches
fetch_batch_compositions <- function(pools, network = "polygon", batch_size = BATCH_SIZE) {
  if (length(pools) == 0) {
    cat("⚠️  No pools to fetch\n")
    return(list())
  }
  
  # Split pools into batches of batch_size
  num_batches <- ceiling(length(pools) / batch_size)
  all_results <- list()
  
  cat(sprintf("📦 Fetching %d pools on %s in %d batch(es)\n", 
              length(pools), network, num_batches))
  
  for (batch_idx in 1:num_batches) {
    start_idx <- (batch_idx - 1) * batch_size + 1
    end_idx <- min(batch_idx * batch_size, length(pools))
    batch_pools <- pools[start_idx:end_idx]
    
    cat(sprintf("  Batch %d/%d: pools %d-%d... ", 
                batch_idx, num_batches, start_idx, end_idx))
    
    response <- tryCatch({
      # Force pools to be JSON array (not string) by using as.list()
      POST(
        url = paste0(API_ENDPOINT, "?network=", network),
        body = list(pools = as.list(batch_pools)),
        encode = "json",
        content_type_json(),
        timeout(30)
      )
    }, error = function(e) {
      cat(sprintf("❌ Error: %s\n", e$message))
      return(NULL)
    })
    
    if (is.null(response)) {
      cat("❌ Failed (connection error)\n")
      next
    }
    
    if (status_code(response) != 200) {
      cat(sprintf("❌ Failed (HTTP %d)\n", status_code(response)))
      error_content <- tryCatch(content(response, "text"), error = function(e) "")
      if (nchar(error_content) > 0) {
        cat(sprintf("    Error: %s\n", substr(error_content, 1, 200)))
      }
      next
    }
    
    result <- content(response, "parsed")
    cat(sprintf("✅ %d pools\n", result$count))
    
    # Add results to list with network info
    for (pool_result in result$results) {
      pool_result$network <- network  # Store network for later parsing
      all_results[[pool_result$pool]] <- pool_result
    }
  }
  
  cat(sprintf("✅ Total fetched: %d/%d pools\n", length(all_results), length(pools)))
  return(all_results)
}

# Load coins data and helper functions if not already loaded
if (!exists("coins_data")) {
  coins_data <- tryCatch({
    read.csv("/home/ubuntu/infinitetrading/coins.csv", colClasses = c("character", "character", "character"))
  }, error = function(e) {
    data.frame(symbol = character(), contract = character(), network = character())
  })
}

if (!exists("get_symbol")) {
  get_symbol <- function(contract, network) {
    symbol <- coins_data$symbol[tolower(coins_data$contract) == tolower(contract) & coins_data$network == network]
    if (length(symbol) == 0) return("Unknown")
    else return(symbol)
  }
}

if (!exists("decimals")) {
  decimals <- function(symbol) {
    if (symbol == "WBTC") return(8)
    else if (symbol %in% c("USDC", "USDCN", "USDT", "DAI")) return(6)
    else return(18)
  }
}

# Parse composition result into matrix format matching old pool_comp
parse_composition <- function(comp_result, network = "polygon") {
  if (!comp_result$success) {
    return(NULL)
  }
  
  composition <- comp_result$composition
  if (length(composition) == 0) {
    return(NULL)
  }
  
  n_row <- length(composition)
  asset <- character(n_row)
  isDeposit <- character(n_row)
  assetPair <- character(n_row)
  symbol <- character(n_row)
  amount <- character(n_row)
  price <- character(n_row)
  
  for (i in seq_along(composition)) {
    item <- composition[[i]]
    contract <- tolower(item$asset)
    asset[i] <- contract
    isDeposit[i] <- as.character(item$isDeposit)
    
    # Get symbol from contract
    sym <- get_symbol(contract, network)[1]
    symbol[i] <- sym
    assetPair[i] <- paste(sym, "USD", sep = "-")
    
    # Convert balance from hex BigNumber
    balance_raw <- tryCatch({
      as.numeric(strtoi(item$balance$hex, base = 16))
    }, error = function(e) 0)
    
    # Convert rate from hex BigNumber (1e18 scaled)
    rate_raw <- tryCatch({
      as.numeric(strtoi(item$rate$hex, base = 16))
    }, error = function(e) 0)
    
    # Apply decimals to balance
    d <- decimals(sym)
    amount[i] <- as.character(balance_raw / (10^d))
    
    # Convert rate from 1e18 scale to actual price
    price[i] <- as.character(rate_raw / (10^18))
  }
  
  # Return as matrix to match old pool_comp format
  out <- cbind(asset, isDeposit, assetPair, symbol, amount, price)
  colnames(out) <- c("asset", "isDeposit", "assetPair", "symbol", "amount", "price")
  
  return(out)
}

# Get composition for a specific pool from batched results
get_pool_composition <- function(pool, batched_results) {
  if (is.null(batched_results[[pool]])) {
    return(NULL)
  }
  result <- batched_results[[pool]]
  network <- if (!is.null(result$network)) result$network else "polygon"
  return(parse_composition(result, network))
}

cat("✅ Batched pool composition functions loaded\n")
cat("   - fetch_batch_compositions(pools, network): Fetch multiple pools\n")
cat("   - get_pool_composition(pool, batched_results): Get individual pool from batch\n")
cat("   - Max batch size:", BATCH_SIZE, "pools\n")
