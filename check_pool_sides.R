#!/usr/bin/env Rscript
# Emergency Pool Side Verification Script
# Checks if all pools are on their correct side according to database settings

require(httr)
require(jsonlite)
require(DBI)
require(RMariaDB)

cat("\n========================================\n")
cat("POOL SIDE VERIFICATION REPORT\n")
cat("Time:", as.character(Sys.time()), "\n")
cat("========================================\n\n")

# Load environment variables
env_file <- "~/infinitetrading/src/.env"
if (file.exists(env_file)) {
  readRenviron(env_file)
}

# Source required files
source("~/infinitetrading/src/api/pool_comp_batch.R")

# Direct database connection (no pooling)
db_con <- function() {
  dbConnect(
    RMariaDB::MariaDB(),
    host = Sys.getenv("db_ip"),
    port = as.integer(Sys.getenv("db_port")),
    user = Sys.getenv("db_user"),
    password = Sys.getenv("db_password"),
    dbname = Sys.getenv("db_schema")
  )
}

# Get all active pool sides from database
get_all_sides <- function() {
  con <- db_con()
  on.exit({
    if (exists("con") && !is.null(con)) {
      dbDisconnect(con)
    }
  }, add = TRUE)
  
  networks <- c("polygon", "optimism", "base", "arbitrum", "ethereum")
  all_sides <- data.frame()
  
  for (network in networks) {
    table_name <- paste0(network, "_dhedge_sides")
    wallets_table <- paste0(network, "_dhedge_gas_wallets")
    
    query <- sprintf("
      SELECT 
        sides.pool,
        sides.pair,
        sides.side,
        sides.threshold,
        sides.max_usd,
        sides.share,
        sides.platform,
        sides.slippage,
        '%s' as network
      FROM %s AS sides 
      JOIN %s AS wallets ON sides.pool = wallets.pool 
      WHERE wallets.is_active = 1 AND LOWER(sides.side) != 'hold'
    ", network, table_name, wallets_table)
    
    result <- tryCatch({
      dbGetQuery(con, query)
    }, error = function(e) {
      cat(sprintf("Error querying %s: %s\n", network, e$message))
      data.frame()
    })
    
    if (nrow(result) > 0) {
      all_sides <- rbind(all_sides, result)
    }
  }
  
  return(all_sides)
}

# Get actual pool composition and determine current side
get_actual_side <- function(pool, pair, composition) {
  if (is.null(composition) || nrow(composition) == 0) {
    return(list(side = "unknown", details = "No composition data"))
  }
  
  # Parse pair (e.g., "WBTC-USDC" -> trade_asset="WBTC", base_asset="USDC")
  pair_parts <- strsplit(pair, "-")[[1]]
  if (length(pair_parts) != 2) {
    return(list(side = "unknown", details = "Invalid pair format"))
  }
  
  trade_asset <- pair_parts[1]
  base_asset <- pair_parts[2]
  
  # Find assets in composition (column 4 is symbol)
  trade_row <- which(composition[, 4] == trade_asset)
  base_row <- which(composition[, 4] == base_asset)
  
  if (length(trade_row) == 0 || length(base_row) == 0) {
    return(list(
      side = "unknown", 
      details = sprintf("Assets not found in composition (trade:%s, base:%s)", trade_asset, base_asset)
    ))
  }
  
  # Get amounts (column 5 is amount)
  trade_amount <- as.numeric(composition[trade_row[1], 5])
  base_amount <- as.numeric(composition[base_row[1], 5])
  
  # Get prices (column 6 is price)
  trade_price <- as.numeric(composition[trade_row[1], 6])
  base_price <- as.numeric(composition[base_row[1], 6])
  
  # Calculate USD values
  trade_usd <- trade_amount * trade_price
  base_usd <- base_amount * base_price
  total_usd <- trade_usd + base_usd
  
  # Determine side based on allocation (threshold at 10%)
  if (total_usd < 1) {
    current_side <- "neutral"
    allocation <- 0
  } else {
    allocation <- (trade_usd / total_usd) * 100
    if (allocation > 10) {
      current_side <- "long"
    } else {
      current_side <- "neutral"
    }
  }
  
  details <- sprintf(
    "%s: $%.2f (%.1f%%) | %s: $%.2f (%.1f%%) | Total: $%.2f",
    trade_asset, trade_usd, (trade_usd/total_usd)*100,
    base_asset, base_usd, (base_usd/total_usd)*100,
    total_usd
  )
  
  return(list(side = current_side, details = details, allocation = allocation))
}

# Main verification
cat("Fetching database sides...\n")
all_sides <- get_all_sides()

if (nrow(all_sides) == 0) {
  cat("ERROR: No active pools found in database!\n")
  quit(status = 1)
}

cat(sprintf("Found %d active pool(s) across all networks\n\n", nrow(all_sides)))

# Fetch compositions by network
cat("Fetching pool compositions in batches...\n")
compositions_by_network <- list()

for (network in unique(all_sides$network)) {
  network_pools <- all_sides$pool[all_sides$network == network]
  cat(sprintf("  %s: %d pool(s)... ", network, length(network_pools)))
  
  batch_result <- tryCatch({
    fetch_batch_compositions(network_pools, network)
  }, error = function(e) {
    cat(sprintf("ERROR: %s\n", e$message))
    list()
  })
  
  compositions_by_network[[network]] <- batch_result
  cat(sprintf("✓ (%d fetched)\n", length(batch_result)))
}

cat("\n")
cat("========================================\n")
cat("VERIFICATION RESULTS\n")
cat("========================================\n\n")

# Check each pool
mismatches <- 0
matches <- 0
errors <- 0

for (i in 1:nrow(all_sides)) {
  row <- all_sides[i, ]
  pool <- row$pool
  expected_side <- tolower(row$side)
  pair <- row$pair
  network <- row$network
  
  # Get composition for this pool
  comp_data <- compositions_by_network[[network]][[pool]]
  composition <- if (!is.null(comp_data)) {
    get_pool_composition(pool, compositions_by_network[[network]])
  } else {
    NULL
  }
  
  # Determine actual side
  actual_result <- get_actual_side(pool, pair, composition)
  actual_side <- actual_result$side
  
  # Compare
  status <- if (actual_side == "unknown") {
    "ERROR"
  } else if (actual_side == expected_side) {
    "✓ MATCH"
  } else {
    "✗ MISMATCH"
  }
  
  if (status == "✓ MATCH") {
    matches <- matches + 1
  } else if (status == "✗ MISMATCH") {
    mismatches <- mismatches + 1
  } else {
    errors <- errors + 1
  }
  
  # Print report
  cat(sprintf("[%s] %s\n", status, network))
  cat(sprintf("  Pool:     %s\n", pool))
  cat(sprintf("  Pair:     %s\n", pair))
  cat(sprintf("  Expected: %s\n", expected_side))
  cat(sprintf("  Actual:   %s\n", actual_side))
  cat(sprintf("  Details:  %s\n", actual_result$details))
  cat("\n")
}

# Summary
cat("========================================\n")
cat("SUMMARY\n")
cat("========================================\n")
cat(sprintf("Total Pools:   %d\n", nrow(all_sides)))
cat(sprintf("✓ Matches:     %d (%.1f%%)\n", matches, (matches/nrow(all_sides))*100))
cat(sprintf("✗ Mismatches:  %d (%.1f%%)\n", mismatches, (mismatches/nrow(all_sides))*100))
cat(sprintf("⚠ Errors:      %d (%.1f%%)\n", errors, (errors/nrow(all_sides))*100))
cat("\n")

if (mismatches > 0) {
  cat("⚠️  WARNING: MISMATCHES DETECTED!\n")
  cat("Some pools are not on their expected side.\n")
  quit(status = 2)
} else if (errors > 0) {
  cat("⚠️  WARNING: ERRORS DETECTED!\n")
  cat("Could not verify some pools.\n")
  quit(status = 3)
} else {
  cat("✅ ALL POOLS ARE ON CORRECT SIDES\n")
  quit(status = 0)
}
