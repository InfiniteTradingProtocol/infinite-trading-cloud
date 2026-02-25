require(redux)
require(httr)
require(jsonlite)

# Local Redis client
r <- redux::hiredis()

# Upstash Redis credentials
upstash_url <- "https://wondrous-coral-6083.upstash.io"
token <- "Bearer ARfDAAIjcDE2Zjg1OTU3NmE2ODA0MjY5OGNkM2Y5NDA2ZWQ2ZmE5ZnAxMA"

# Push full yield data to Upstash in one SET call
push_full_yield_map <- function(yield_map, key = "yield_data") {
  # Convert all values to character strings to match Redis string behavior
  for (pool in names(yield_map)) {
    yield_map[[pool]]$totalYield <- as.character(yield_map[[pool]]$totalYield)
    yield_map[[pool]]$APY <- as.character(yield_map[[pool]]$APY)
  }

  json_payload <- toJSON(yield_map, auto_unbox = TRUE)
  encoded_payload <- URLencode(json_payload, reserved = TRUE)

  endpoint <- paste0(upstash_url, "/SET/", key, "/", encoded_payload)
  res <- POST(endpoint, add_headers(Authorization = token))

  return(content(res, "text", encoding = "UTF-8"))
}

# Optional: to fetch and inspect
fetch_yield_map <- function(key = "yield_data") {
  endpoint <- paste0(upstash_url, "/GET/", key)
  res <- GET(endpoint, add_headers(Authorization = token))
  json_text <- content(res, "text", encoding = "UTF-8")
  fromJSON(json_text)
}

# Load pool helpers
source("~/infinitetrading/src/api/helpers/graphQL.R")
source("~/infinitetrading/src/api/helpers/yieldPools.R")

# Start the yield update loop
while (1) {
  yield_map <- list()

  for (pool in pools) {
    pool_map <- pool_mapping(pool = pool)
    initial_price <- pool_map$price

    if (pool_map$benchmark != "USD") {
      actual_price <- getTicks(exchange = "coinbase", pair = pool_map$benchmark)
    } else {
      actual_price <- 1
    }

    benchmark_return <- (actual_price - initial_price) / initial_price

    priceHistory <- getPoolTokenPrice(protocol = "dhedge", pool = pool, period = "1d")
    Sys.sleep(1)

    inceptionDate <- pool_map$date
    date_parsed <- as.Date(inceptionDate, format = "%Y-%m-%d %I:%M:%S %p")
    number_of_days <- as.numeric(Sys.Date() - date_parsed)

    token_return <- as.numeric(tail(priceHistory[, 2], 1))
    totalYield <- token_return - benchmark_return
    apy <- (1 + totalYield)^(365 / number_of_days) - 1

    # Console output
    cat("\n====================\n")
    cat("dHEDGE Vault: ", pool_map$name, " ( https://www.dhedge.org/vault/", pool, " )\n", sep = "")
    cat("Vault Creation: ", pool_map$date, "\n", sep = "")
    cat("Network: ", pool_map$network, "\n", sep = "")
    cat(pool_map$benchmark, " returns since inception: ", round(benchmark_return * 100, 2), "%\n", sep = "")
    cat("Vault Returns since inception: ", round(token_return * 100, 2), "%\n", sep = "")
    cat("Vault Yield since inception: ", round(totalYield * 100, 2), "%\n", sep = "")
    cat("Estimated APY: ", round(apy * 100, 2), "%\n", sep = "")
    cat("====================\n")

    # Push to local Redis
    r$SET(paste0(pool, "_totalYield"), totalYield)
    r$SET(paste0(pool, "_APY"), apy)

    # Add to bulk push map
    yield_map[[pool]] <- list(
      totalYield = totalYield,
      APY = apy
    )
  }

  # Push the entire structure to Upstash
  result <- push_full_yield_map(yield_map)
  cat("Upstash result: ", result, "\n")

  # Sleep for 10 minutes
  Sys.sleep(60 * 10)
}

