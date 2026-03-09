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
    
    # Add results to list
    for (pool_result in result$results) {
      all_results[[pool_result$pool]] <- pool_result
    }
  }
  
  cat(sprintf("✅ Total fetched: %d/%d pools\n", length(all_results), length(pools)))
  return(all_results)
}

# Parse composition result into data frame format
parse_composition <- function(comp_result) {
  if (!comp_result$success) {
    return(NULL)
  }
  
  composition <- comp_result$composition
  if (length(composition) == 0) {
    return(NULL)
  }
  
  # Convert to data frame
  df <- data.frame(
    asset = sapply(composition, function(x) x$asset),
    isDeposit = sapply(composition, function(x) x$isDeposit),
    balance_hex = sapply(composition, function(x) x$balance$hex),
    rate_hex = sapply(composition, function(x) x$rate$hex),
    stringsAsFactors = FALSE
  )
  
  # Convert hex BigNumber to numeric
  df$balance <- sapply(df$balance_hex, function(hex) {
    tryCatch(as.numeric(strtoi(hex, base = 16)), error = function(e) 0)
  })
  
  df$rate <- sapply(df$rate_hex, function(hex) {
    tryCatch(as.numeric(strtoi(hex, base = 16)), error = function(e) 0)
  })
  
  return(df)
}

# Get composition for a specific pool from batched results
get_pool_composition <- function(pool, batched_results) {
  if (is.null(batched_results[[pool]])) {
    return(NULL)
  }
  return(parse_composition(batched_results[[pool]]))
}

cat("✅ Batched pool composition functions loaded\n")
cat("   - fetch_batch_compositions(pools, network): Fetch multiple pools\n")
cat("   - get_pool_composition(pool, batched_results): Get individual pool from batch\n")
cat("   - Max batch size:", BATCH_SIZE, "pools\n")
