require(plumber); require(lubridate); require(jsonlite); require(httr);

require(future); require(promises); plan(multicore); options(future.multicore.workers = parallel::detectCores())

#require(memoise)

# Determine repo root - works whether script is run directly or sourced
if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
  script_dir = dirname(normalizePath(ofile))
} else {
  # Fallback: use current working directory
  script_dir = normalizePath(".")
}

# Navigate to repo root
if (basename(script_dir) == "plumber" || basename(script_dir) == "api") {
  wd = dirname(script_dir)
} else if (file.exists(file.path(script_dir, "plumber", "api.R"))) {
  wd = script_dir  # Already at root
} else if (file.exists(file.path(script_dir, "api", "api.R"))) {
  wd = script_dir  # Already at root (src structure)
} else if (file.exists(file.path(script_dir, "src", "api", "api.R"))) {
  # Running from repo root with src structure
  wd = script_dir
} else {
  # Try going up one level
  wd = dirname(script_dir)
}
wd = paste0(normalizePath(wd), "/")

sources = function(files) { for (i in 1:length(files)) { source(paste0(wd,files[i])) } }

# Try to load connection pool if available (same directory as api.R)
pool_loaded = FALSE
if(exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
  local_pool = file.path(dirname(normalizePath(ofile)), "db_pool.R")
} else {
  local_pool = file.path(normalizePath("."), "db_pool.R")
}

if (file.exists(local_pool)) {
  tryCatch({
    source(local_pool)
    pool_loaded = TRUE
    cat("Connection pool loaded from:", local_pool, "\n")
  }, error = function(e) {
    warning(paste("Failed to load pool:", e$message))
  })
}

# Detect directory structure and source accordingly
if (file.exists(paste0(wd, "plumber/db.R"))) {
  # Local development structure
  sources(c("plumber/db.R","plumber/messaging.R","plumber/encryption.R","plumber/getGasBalances.R","plumber/helpers/graphQL.R","plumber/helpers/apiHelpers.R","plumber/helpers/yieldPools.R","plumber/helpers/cex_helpers.R","plumber/executeTrades.R","tradebot/tradebot.R"))
} else if (file.exists(paste0(wd, "src/api/db.R"))) {
  # EC2/production structure (all files in src/api/ and src/tradebot/)
  sources(c("src/api/db.R","src/api/messaging.R","src/api/encryption.R","src/api/getGasBalances.R","src/api/helpers/graphQL.R","src/api/helpers/apiHelpers.R","src/api/helpers/yieldPools.R","src/api/helpers/cex_helpers.R","src/api/executeTrades.R","src/tradebot/tradebot.R"))
} else if (file.exists(paste0(wd, "api/db.R"))) {
  # Running from src/ directory (PM2 case)
  sources(c("api/db.R","api/messaging.R","api/encryption.R","api/getGasBalances.R","api/helpers/graphQL.R","api/helpers/apiHelpers.R","api/helpers/yieldPools.R","api/helpers/cex_helpers.R","api/executeTrades.R","tradebot/tradebot.R"))
} else {
  stop(paste0("Could not detect directory structure. wd=", wd, " script_dir=", script_dir))
}

# Reusable activity reporter
report_activity <- function(endpoint, apiKey, pool, protocol, network, platform, status, status_code = NA_integer_, message = "") {
    masked_api <- mask_api(apiKey)
    msg <- paste0(status, " ", endpoint, " invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / platform: ", platform,
                  " / status_code: ", status_code,
                  " / response: ", message)
    print(msg)
    send_telegram_text(msg)
    #discord(msg = msg, channel = "#api-logs", db = TRUE)
}

#fetch_data <- memoise(function(query,params) {
#  conn = db_con()
#  result <- dbGetQuery(conn, query,params=params)
#  dbDisconnect(conn)
#  return(result)
#})
#Sys.env()

#return(0)
# Run the API
# Initialize a list to track requests

options(error = recover)

#express endpoint

ep = "http://localhost:8000/"
pr <- Plumber$new()

#========================================================================================================================

#clear_cache <- function() { forget(fetch_data) }
#pr$handle("POST", "/clear_cache", function() {
#		    clear_cache()
#		      return(list(message = "Cache cleared"))
#})

#========================================================================================================================

get_contract <- function(coin, network) {
	if (!isValidEthereumAddress(coin)) { coins(coin,network,discord=FALSE) }
	else { coin }
}
getContractHandler <- function(coin,network) { get_contract(coin,network) }
pr$handle("GET", "/getContract", getContractHandler, comment ="
	  # @summary Get Contract Information
	  # @description Retrieves contract information for a specified coin on a given network.
	  # @param coin The coin symbol (e.g., 'WBTC', 'WETH', 'WMATIC') as a query parameter.
	  # @param network The network to query (e.g., 'polygon', 'optimism') as a query parameter.
	  # @response 200 Successful operation
	  # @response 400 Invalid request parameters
	  ")

#========================================================================================================================

# poolComposition migrated to Express (poolCompositionEnriched.ts), cut over in nginx.
# nginx no longer routes /poolComposition here; gateway wrapper endpoints/poolComposition.R removed.

#========================================================================================================================

setAllocationsHandler = function(apiKey, protocol, pool, network, assets, allocations, lower_thresholds, upper_thresholds, slippages, max_usd,platform) {
	if (isValidApiKey(network,protocol,pool,apiKey)) { setAllocations(protocol = protocol, pool = pool, network = network, assets = assets, allocations = allocations, lower_thresholds = lower_thresholds, upper_thresholds = upper_thresholds,slippages = slippages,max_usd=max_usd,platform=platform) }
	else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}

pr$handle("POST", "/setAllocations", setAllocationsHandler, serializer = serializer_json())

#========================================================================================================================

getAllocationsHandler = function(apiKey, protocol, pool, network) {
	if (isValidApiKey(network,protocol,pool,apiKey)) { getAllocations(protocol = protocol, pool = pool, network = network) }
	else { res = c(); res$status = 401; list(status <- "fail",status_code = 401,message <- "Invalid API key") }
}

pr$handle("POST", "/getAllocations", getAllocationsHandler, serializer = serializer_json())

#========================================================================================================================

# createWalletHandler + /createWallet REMOVED 2026-09-06 — cut over to Express
# (port 8000), see src/requests/createGasWallet.ts in infinitetrading_api/express,
# which generates the keypair and its API token directly. nginx now routes
# /createGasWallet to Express and the gateway wrapper createGasWallet.R is gone.

#========================================================================================================================

# approveHandler + /approve REMOVED 2026-09-06 — cut over to Express (port
# 8000), see src/requests/approve.ts in infinitetrading_api/express, which
# replicates this handler's full validation chain (symbol aliasing,
# isValidApiKey, contract resolution, BULL/BEAR -> toros, 3-attempt retry)
# in front of Express's raw /approveRaw. nginx no longer routes /approve here
# and the gateway wrapper approve.R is gone.

#========================================================================================================================

# getApiKeyHandler + /getApiKey REMOVED 2026-09-06 — cut over to Express (port
# 8000), see src/requests/getNewApiKey.ts in infinitetrading_api/express, which
# ports isValidEthPrivateKey() and calls walletv2.generateApiToken() directly.
# nginx now routes /getNewApiKey to Express; gateway wrapper getNewApiKey.R is gone.

#========================================================================================================================

getWallet = function(apiKey) {
	url <- paste0(ep,"getWallet?apiKey=",apiKey)
        response <- GET(url); response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
        if (status_code(response) == 200) { return(parsed_response$msg) }
	else { return(list(status="fail",status_code=status_code(response),message=parsed_response)) }
}


#========================================================================================================================

# linkGasWalletHandler REMOVED 2026-09-06 — cut over to Express (port 8000),
# see src/requests/linkGasWallet.ts in infinitetrading_api/express. nginx no
# longer routes /linkGasWallet here — see ops/nginx/generate-endpoints-conf.sh's
# CUTOVER_ENDPOINTS mechanism.

#========================================================================================================================

# getGasBalance moved to Express (port 8000) — see
# infinitetrading_api/express/src/requests/gasBalance.ts.

#========================================================================================================================

# getAllGasBalance moved to Express (port 8000) — see
# infinitetrading_api/express/src/requests/gasBalance.ts.

#========================================================================================================================

# getAllBots moved to Express (port 8000) — see
# infinitetrading_api/express/src/requests/getAllBots.ts.

#========================================================================================================================

# unlinkGasWalletHandler REMOVED 2026-09-06 — cut over to Express (port
# 8000), see src/requests/unlinkGasWallet.ts in infinitetrading_api/express.
# nginx no longer routes /unlinkGasWallet here.

# setSideHandler + /setSide REMOVED 2026-09-06 — cut over to Express
# (port 8000): the entire setBot/tradebot/executeTrades decision engine
# was ported to infinitetrading_api/express/src/tradeEngine.ts +
# src/requests/setBot.ts. nginx no longer routes /setBot here.

#========================================================================================================================

getSideHandler = function(apiKey,protocol,pool,network) {
        if (isValidApiKey(network,protocol,pool,apiKey)) { getSide(protocol=protocol,pool=pool,network=network) }
        else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}
pr$handle("POST","/getSide",getSideHandler, serializer = serializer_json())


#========================================================================================================================

# deleteBotHandler REMOVED 2026-09-06 — cut over to Express (port 8000), see
# src/requests/deleteBot.ts in infinitetrading_api/express. nginx no longer
# routes /deleteBot here.

#========================================================================================================================

getSupportedAssetsHandler = function(apiKey,network) { getSupportedAssets(network) }
pr$handle("POST","/getSupportedAssets",getSupportedAssetsHandler, serializer = serializer_json())

#========================================================================================================================

# getCandlesHandler REMOVED 2026-09-06 — cut over to Express (port 8000),
# see src/requests/getCandles.ts in infinitetrading_api/express. nginx no
# longer routes /getCandles here.

#========================================================================================================================

# getTicksHandler / getTotalYieldHandler / getEstimatedAnualYieldHandler /
# getAllYieldsHandler REMOVED 2026-09-06 — cut over to Express (port 8000),
# see src/requests/yields.ts and src/requests/getTicks.ts in infinitetrading_api/express.
# These read straight from Redis with no other dependency on this file, and
# nginx no longer routes /getTicks, /getTotalYield, /getEstimatedAnualYield,
# /getAllYields here — see ops/nginx/generate-endpoints-conf.sh's
# CUTOVER_ENDPOINTS mechanism.

#========================================================================================================================

# getGasWalletPools moved to Express (port 8000) — see
# infinitetrading_api/express/src/requests/getGasWalletPools.ts.

#========================================================================================================================

# associateGasWalletHandler REMOVED 2026-09-06 — cut over to Express (port
# 8000), see src/requests/associateGasWallet.ts in infinitetrading_api/express.
# nginx no longer routes /associateGasWallet here.

#========================================================================================================================


#========================================================================================================================

# getAssociatedGasWallets moved to Express (port 8000) — see
# infinitetrading_api/express/src/requests/getAssociatedGasWallets.ts.

#========================================================================================================================

#========================================================================================================================

# deassociateGasWalletHandler REMOVED 2026-09-06 — cut over to Express (port
# 8000), see src/requests/deassociateGasWallet.ts in infinitetrading_api/express.
# nginx no longer routes /deassociateGasWallet here.

#========================================================================================================================

#========================================================================================================================

# mintFeesHandler + /mintFees REMOVED 2026-09-06 — dead code: not present in
# endpoints.R (never publicly exposed via any gateway wrapper) and no other
# internal caller found. The endpoint it proxied to, /mintManagerFee, is
# already live on Express (port 8000), see requests/admin.ts.

#========================================================================================================================

#========================================================================================================================

# vaultTradeHandler + /vaultTrade REMOVED 2026-09-06 — cut over to Express
# (port 8000), see src/requests/vaultTrade.ts in infinitetrading_api/express.
# nginx no longer routes /vaultTrade here.

#========================================================================================================================

# repayHandler, borrowHandler, lendHandler, unlendHandler,
# getHealthFactorHandler, getPoolAaveDataHandler, getBorrowedHandler,
# getSuppliedHandler + their /repay, /borrow, /lend, /unlend,
# /getHealthFactor, /getPoolAaveData, /getBorrowed, /getSupplied routes
# REMOVED 2026-09-06 — cut over to Express (port 8000), see
# src/requests/lend.ts, unlend.ts, borrow.ts, repay.ts, getHealthFactor.ts,
# getPoolAaveData.ts in infinitetrading_api/express (getBorrowed/getSupplied
# were already served directly by Express's own /getBorrowed, /getSupplied
# and are now called from the new aaveV3.ts sub-router wrapper instead of
# through this port-8002 layer). nginx no longer routes /lend, /unlend,
# /borrow, /repay, /getHealthFactor, /getPoolAaveData here.


#========================================================================================================================
# CEX Trading Endpoints
#========================================================================================================================
# ALL CEX endpoints REMOVED 2026-09-06 - cut over to Express (port 8000).
# Ported to infinitetrading_api/express/src/requests/cexPublic.ts:
#   /registerCEXSubaccount, /setCEXSide, /getCEXSide, /setCEXStrategy,
#   /deleteCEXBot, /deactivateCEXBot, /deleteCEXSubaccount,
#   /getAllCEXSubaccounts
# nginx no longer routes any of these here.
#
# NOTE: 6 of these handlers called encrypt_gas_wallet_api_key(), a function
# that was never defined anywhere in this codebase, so they had been returning
# HTTP 500 in production since at least 2026-08-27. The Express port replaces
# that call with a deterministic keyed HMAC token
# (see express/src/utils/cexCrypto.ts, gasWalletApiKeyToken).
#
# The AES-CTR credential encryption in cex_encryption_compact.R is STILL USED
# by the cex-tradebot service, so that file is deliberately left in place.


pr$run(host="127.0.0.1",port=8002)
