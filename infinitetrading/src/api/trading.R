require(lubridate)

# Get the directory of THIS script (api/) not the working directory
# Script is in /home/ubuntu/infinitetrading/src/api/
script_dir <- "/home/ubuntu/infinitetrading/src/api"
# Load the connection pool
pool_paths <- c("../db_pool.R", "/home/ubuntu/infinitetrading/src/db_pool.R", paste0(script_dir, "/../db_pool.R"))
for (pool_path in pool_paths) {
  if (file.exists(pool_path)) {
    source(pool_path)
    break
  }
}

load_dependencies <- function() {
  require(httr)
  require(slackr)
  require(stringr)
  require(jsonlite)
  require(DBI)
  require(RMariaDB)
  require(redux)
}

load_dependencies()

bot_network <- Sys.getenv("network")
cat("bot network is:", bot_network, "\n")
if (bot_network == "") {
  cat("No specific network set; will monitor all networks\n")
  bot_network <- NULL
}

# Set paths for sourcing - use parent directory (src/) for db.R, script_dir for api/ files
src_dir <- "/home/ubuntu/infinitetrading/src/"
wd <- src_dir

source(paste0(script_dir, "/db.R"))
source(paste0(script_dir, "/encryption.R"))
source(paste0(script_dir, "/messaging.R"))
source(paste0(script_dir, "/executeTrades.R"))
source(paste0(script_dir, "/pool_comp_batch.R"))  # 🚀 Batch fetching
# Set flag to prevent defi.R from re-sourcing db.R
DEFI_SKIP_SOURCES <- TRUE
source(paste0(src_dir, "tradebot/defi.R"))
source(paste0(src_dir, "tradebot/tradebot.R"))
source(paste0(script_dir, "/helpers/apiHelpers.R"))

# Helper function to get all active pools for a network
getActivePools <- function(protocol, network) {
  con <- db_con()
  on.exit({
    if (exists("con") && !is.null(con)) {
      dbDisconnect(con)
    }
  }, add = TRUE)

  # Unified schema: dhedge_sides + gas_wallets (pool IS NOT NULL = linked)
  query <- "SELECT DISTINCT ds.pool
            FROM dhedge_sides ds
            JOIN gas_wallets gw ON gw.pool = ds.pool AND gw.network = ds.network
            WHERE ds.network = ? AND gw.protocol = ? AND gw.is_active = 1
              AND LOWER(ds.side) != 'hold'"

  pools <- tryCatch({
    dbGetQuery(con, query, params = list(network, protocol))$pool
  }, error = function(e) {
    cat(sprintf("Error getting active pools for %s/%s: %s\n", network, protocol, e$message))
    character(0)
  })

  return(pools)
}

monitorSides <- function(protocol, network, report, batched_compositions = NULL) {
  con <- db_con()  # Connect to RDS
  on.exit({
    if (exists("con") && !is.null(con)) {
      dbDisconnect(con)
    }
  }, add = TRUE)
  
  # Unified schema: dhedge_sides + gas_wallets (pool IS NOT NULL = linked)
  query <- "SELECT ds.pool, ds.pair, ds.side, ds.threshold, ds.max_usd, ds.share, ds.platform, ds.slippage
            FROM dhedge_sides ds
            JOIN gas_wallets gw ON gw.pool = ds.pool AND gw.network = ds.network
            WHERE ds.network = ? AND gw.protocol = ? AND gw.is_active = 1
              AND LOWER(ds.side) != 'hold'"

  tryCatch({
    res <- dbSendQuery(con, query, params = list(network, protocol))
    on.exit(dbClearResult(res), add = TRUE)
    while (TRUE) {
      row <- dbFetch(res, n = 1)
      if (nrow(row) == 0) break
      print(row)

      pool = row$pool
      apiKey = getAPIKey(protocol=protocol, network=network, pool=pool)
      print(paste0("monitoring a vault using this api key: ", apiKey))

      side = row$side
      max_usd = row$max_usd
      pair = row$pair
      threshold = row$threshold
      share = row$share
      platform = row$platform
      slippage = row$slippage
      
      # 🚀 Use pre-fetched composition if available, otherwise fetch individually
      if (!is.null(batched_compositions)) {
        composition <- get_pool_composition(pool, batched_compositions)
        if (is.null(composition)) {
          cat(sprintf("⚠️  Pool %s not in batch, fetching individually\n", pool))
          composition <- pool_comp(network=network, protocol=protocol, pool=pool, apiKey=apiKey, provider="alchemy")
        }
      } else {
        composition <- pool_comp(network=network, protocol=protocol, pool=pool, apiKey=apiKey, provider="alchemy")
      }
      
      msg = paste0(
        "apiKey: ", mask_api(apiKey), 
        " / pool: https://www.dhedge.org/vault/", pool,
        " / side: ", side, 
        " / pair: ", pair, 
        " / threshold: ", threshold, 
        " / max_usd: ", max_usd, 
        " / share: ", share, 
        " / platform: ", platform, 
        " / slippage: ", slippage, 
        " / network: ", network, 
        " / protocol: ", protocol
      )
      print(msg)
      if (report) { 
        discord(channel="#api-pools", msg=msg)
        send_telegram_text(msg, chat_id="-4874224616")
      }
      
      executeTrades_res <- executeTrades(
        pool=pool, pair=pair, side=side, share=share,
        threshold=threshold, slippage=slippage, apiKey=apiKey,
        max_usd=max_usd, composition=composition,
        platform=platform, protocol=protocol, network=network
      )
      print(executeTrades_res)
      Sys.sleep(1)
    }
  }, error = function(e) {
    cat("An error occurred monitoring sides for protocol: ", protocol, " network: ", network, " error: ")
    print("Error details:")
    print(e)
  })
}

report_hour = -1
report = TRUE
repeat { 
  this_hour = hour(Sys.time())
  if (this_hour != report_hour) { report = TRUE; report_hour = this_hour }
  
  # 🚀 BATCH FETCH: Get all active pools and fetch compositions in batches per network
  cat("\n🔄 Fetching pool compositions for all networks in batches...\n")
  compositions_by_network <- list()  # Store compositions organized by network
  networks <- c("polygon", "optimism", "base", "arbitrum", "ethereum")
  
  for (net in networks) {
    active_pools <- getActivePools(protocol="dhedge", network=net)
    
    if (length(active_pools) > 0) {
      cat(sprintf("  📦 Network %s: %d active pool(s)\n", net, length(active_pools)))
      batch_result <- tryCatch({
        fetch_batch_compositions(active_pools, net)
      }, error = function(e) {
        cat(sprintf("  ❌ Error fetching %s pools: %s\n", net, e$message))
        list()
      })
      
      # Store compositions for THIS network only
      compositions_by_network[[net]] <- batch_result
      cat(sprintf("  ✅ Fetched %d composition(s) for %s\n", length(batch_result), net))
    } else {
      cat(sprintf("  ⏭️  Network %s: No active pools\n", net))
      compositions_by_network[[net]] <- list()
    }
  }
  
  total_comps <- sum(sapply(compositions_by_network, length))
  cat(sprintf("✅ Fetched %d pool compositions total across all networks\n\n", total_comps))
  
  # Monitor each network with ONLY its own pre-fetched compositions
  monitorSides(protocol="dhedge", network="polygon", report=report, batched_compositions=compositions_by_network[["polygon"]])
  monitorSides(protocol="dhedge", network="optimism", report=report, batched_compositions=compositions_by_network[["optimism"]])
  monitorSides(protocol="dhedge", network="base", report=report, batched_compositions=compositions_by_network[["base"]])
  monitorSides(protocol="dhedge", network="arbitrum", report=report, batched_compositions=compositions_by_network[["arbitrum"]])
  monitorSides(protocol="dhedge", network="ethereum", report=report, batched_compositions=compositions_by_network[["ethereum"]])
  
  if (report) { report = FALSE }
  Sys.sleep(10)
}
