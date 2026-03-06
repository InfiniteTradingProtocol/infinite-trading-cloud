# Test script for batch pool composition fetching
# This tests the new multicall batch endpoint

require(httr)
require(jsonlite)

# Configuration
API_URL <- "http://localhost:8000/poolCompositionBatch"

# Test pools from different networks (from pools.R)
test_pools <- list(
  polygon = c(
    "0xb48a390270d41a1663a68708210b7ef4d89ba9f6",  # Zeus BTC pool
    "0x4bc2ee59d978a107addc3ab934722c4f01425b9e",  # Another polygon pool
    "0xd28073e24a2e1dfae3ea48a66a6c1003e2836241"   # Another polygon pool
  ),
  optimism = c(
    "0x3f9f29af59b0918b4f5f16d2455d7fe95f96b2cf",  # OP pool 1
    "0x741784f8bd84aa8dd5f8dc7697fff75f671c343f"   # OP pool 2
  ),
  base = c(
    "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d",  # Base pool 1
    "0xda240cd18041a0153de6348196c62b9267c4d118"   # Base pool 2
  )
)

# Function to fetch batch pool compositions
fetch_batch_compositions <- function(pools, network = "polygon") {
  cat(sprintf("\n=== Fetching %d pools on %s ===\n", length(pools), network))
  
  start_time <- Sys.time()
  
  response <- tryCatch({
    POST(
      url = paste0(API_URL, "?network=", network),
      body = list(pools = pools),
      encode = "json",
      content_type_json(),
      timeout(30)
    )
  }, error = function(e) {
    cat("ERROR:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(response)) return(NULL)
  
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  
  if (status_code(response) != 200) {
    cat("ERROR: HTTP", status_code(response), "\n")
    print(content(response, "text"))
    return(NULL)
  }
  
  result <- content(response, "parsed")
  
  cat(sprintf("✅ SUCCESS! Fetched %d pools in %.2f seconds\n", result$count, elapsed))
  cat(sprintf("   RPC efficiency: %d pools in ONE multicall\n", result$count))
  
  return(result$results)
}

# Function to parse composition into the expected format
parse_composition <- function(comp_result) {
  if (!comp_result$success) {
    cat("  ⚠️  Failed:", comp_result$error, "\n")
    return(NULL)
  }
  
  composition <- comp_result$composition
  
  # Convert to data frame format similar to existing code
  df <- data.frame(
    asset = sapply(composition, function(x) x$asset),
    isDeposit = sapply(composition, function(x) x$isDeposit),
    balance_hex = sapply(composition, function(x) x$balance$hex),
    rate_hex = sapply(composition, function(x) x$rate$hex),
    stringsAsFactors = FALSE
  )
  
  # Convert hex to numeric (simulating BigNumber conversion)
  # In real implementation, you'd use proper BigInt library
  df$balance_dec <- sapply(df$balance_hex, function(hex) {
    as.numeric(strtoi(hex, base = 16))
  })
  
  df$rate_dec <- sapply(df$rate_hex, function(hex) {
    as.numeric(strtoi(hex, base = 16))
  })
  
  return(df)
}

# Test function to compare old vs new approach
compare_approaches <- function() {
  cat("\n" , rep("=", 60), "\n")
  cat("COMPARISON: Old (individual) vs New (batch) approach\n")
  cat(rep("=", 60), "\n")
  
  test_network <- "polygon"
  test_pool_list <- test_pools[[test_network]]
  
  # Old approach simulation (would make N RPC calls)
  cat("\n📊 OLD APPROACH (individual calls):\n")
  cat(sprintf("   Would make %d separate API calls\n", length(test_pool_list)))
  cat(sprintf("   Each call = 1 RPC for manager + 1 RPC for composition\n"))
  cat(sprintf("   Total: %d RPC calls\n", length(test_pool_list) * 2))
  
  # New approach (batch)
  cat("\n🚀 NEW APPROACH (batch multicall):\n")
  results <- fetch_batch_compositions(test_pool_list, test_network)
  
  if (!is.null(results)) {
    cat("\n📋 Processing individual pools:\n")
    for (i in seq_along(results)) {
      result <- results[[i]]
      cat(sprintf("\nPool %d: %s\n", i, substr(result$pool, 1, 10), "..."))
      
      if (result$success) {
        comp_df <- parse_composition(result)
        if (!is.null(comp_df)) {
          cat(sprintf("  ✅ Assets: %d\n", nrow(comp_df)))
          cat("  Top 2 assets:\n")
          for (j in 1:min(2, nrow(comp_df))) {
            cat(sprintf("    - %s (deposit: %s)\n", 
                       substr(comp_df$asset[j], 1, 10), 
                       comp_df$isDeposit[j]))
          }
        }
      }
    }
  }
  
  cat("\n", rep("=", 60), "\n")
}

# Run comparison test
cat("\n🧪 TESTING BATCH POOL COMPOSITION ENDPOINT\n")
compare_approaches()

cat("\n✅ Test complete!\n")
cat("\nNEXT STEPS:\n")
cat("1. Modify defi_thread.R to fetch all pools at start in batches by network\n")
cat("2. Cache compositions and update periodically (e.g., every 5 minutes)\n")
cat("3. Each pool checks its cached composition instead of individual API calls\n")
cat("4. Reduce 73+ calls per loop to 2-3 batch calls total\n")
