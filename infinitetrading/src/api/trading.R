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
# Set flag to prevent defi.R from re-sourcing db.R
DEFI_SKIP_SOURCES <- TRUE
source(paste0(src_dir, "tradebot/defi.R"))
source(paste0(src_dir, "tradebot/tradebot.R"))
source(paste0(script_dir, "/helpers/apiHelpers.R"))

monitorSides <- function(protocol, network, report) {
  con <- db_con(use_pool=FALSE)  # Use RDS for persistent pool data
  on.exit({
    if (exists("con") && !is.null(con)) {
      dbDisconnect(con)  # RDS connections are not pooled
    }
  }, add = TRUE)
  
  table_name <- paste0(network, "_", protocol, "_sides")
  wallets_table <- paste0(network, "_", protocol, "_gas_wallets")
  query <- sprintf(" SELECT sides.* FROM %s AS sides JOIN %s AS wallets ON sides.pool = wallets.pool WHERE wallets.is_active = 1 AND LOWER(sides.side) != 'hold'", table_name, wallets_table)
  
  tryCatch({
    res <- dbSendQuery(con, query)
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
      composition = pool_comp(network=network, protocol=protocol, pool=pool, apiKey=apiKey, provider="alchemy")
      
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
  
  monitorSides(protocol="dhedge", network="polygon", report=report)
  monitorSides(protocol="dhedge", network="optimism", report=report)
  monitorSides(protocol="dhedge", network="base", report=report)
  monitorSides(protocol="dhedge", network="arbitrum", report=report)
  monitorSides(protocol="dhedge", network="ethereum", report=report)
  
  if (report) { report = FALSE }
  Sys.sleep(10)
}
