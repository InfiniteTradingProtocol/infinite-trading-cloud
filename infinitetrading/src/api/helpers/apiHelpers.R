#dependencies
require(dotenv); require(data.table); require(DBI); require(RSQLite); require(lubridate); require(jsonlite); require(httr);

# Environmental variables - comment out for now, will load from parent
# load_dot_env("~/infinitetrading/src/api/.env")

# These are now sourced from parent script
# source("~/infinitetrading/src/api/helpers/graphQL.R")
# source("~/infinitetrading/src/api/getGasBalances.R")

# Use relative path - assume coins.csv is in repo root
coins_csv_path = "/home/ubuntu/infinitetrading/coins.csv"
if (file.exists(coins_csv_path)) {
  coins_data <- read.csv(coins_csv_path, colClasses = c("character", "character", "character"))
} else {
  print(paste0("Warning: coins.csv not found at ", coins_csv_path))
  coins_data <- data.frame(contract=character(), network=character(), symbol=character())
}

networks = c("ethereum","arbitrum","optimism","polygon","base")
getSupportedAssets <- function(network) {
 contracts <- coins_data$contract[coins_data$network == network]
 if (length(contracts) == 0) return(NULL)
 return(contracts)
}

getContract <- function(asset, network) {
 contract <- coins_data$contract[tolower(coins_data$symbol) == tolower(asset) & tolower(coins_data$network) == tolower(network)]
 if (length(contract) == 0) return(NULL)
 return(contract)
}

get_decimals = function(asset) {
        if (asset == "WBTC") { decimals = 8 }
        else if (asset == "USDC" || asset == "USDT" || asset == "USDCN") { decimals = 6 }
        else { decimals = 18 }
        return(decimals)
}
#print(getContract("WBTC","polygon"))

#endpoints
ep ="http://localhost:8000/"
pep="http://localhost:8002/"

# Initialize SQLite database

db <- RSQLite::dbConnect(SQLite(), "api_logs.sqlite")
RSQLite::dbExecute(db, "
  CREATE TABLE IF NOT EXISTS api_logs (
    id INTEGER PRIMARY KEY,
    timestamp TEXT,
    endpoint TEXT,
    api_key TEXT,
    ip TEXT
  )
")
if (RSQLite::dbExistsTable(db, "api_logs")) {
  print("Connection successful, and table exists.")
} else {
  stop("Table does not exist or database file is invalid.")
}

isValidAPIKey <- function(api_key) {
  # API keys are now UUID v4 tokens (36 chars with hyphens)
  if (!is.character(api_key) || length(api_key) != 1 || is.na(api_key)) return(FALSE)
  return(grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
               api_key, ignore.case=TRUE, perl=TRUE))
}

isValidTrader <- function(protocol,pool,trader) {
	poolTrader = tolower(getPoolTrader(protocol,pool))
	if (poolTrader == tolower(trader)) return(TRUE)
	return(FALSE)
}

isValidEthereumAddress <- function(address) {
  if (is.null(address) || length(address) != 1 || is.na(address)) return(FALSE)
  pattern <- "^0x[a-fA-F0-9]{40}$"
  if (grepl(pattern, as.character(address), perl = TRUE)) return(TRUE)
  return(FALSE)
}

mask_api <- function(api_key) {
  api_length <- nchar(api_key)
  return(paste0("***",substr(api_key, api_length - 4, api_length)))
}

isValidEthPrivateKey <- function(privateKey) {
    if (startsWith(privateKey, "0x")) { privateKey <- substr(privateKey, 3, nchar(privateKey)) }
    return(nchar(privateKey) == 64 && grepl("^[0-9a-fA-F]+$", privateKey))
}



assetToContract = function(asset,network) {
	if (isValidEthereumAddress(asset)) return(asset)
	if (asset == "BTC") { asset= "WBTC" }
	else if (asset == "USD") { asset = "USDC" }
	else if (asset == "ETH") { asset = "WETH" }
	else if (asset == "MATIC" || asset == "POL") { asset = "WMATIC" }
	asset = getContract(asset,network)
}

getWallet = function(apiKey) {
	url <- paste0(ep,"getWallet?apiKey=",apiKey)
	response <- GET(url)
	response_content <- content(response, "text")
	parsed_response <- fromJSON(response_content)
	if (status_code(response) == 200) { return(parsed_response$msg) }
	else { return(list(status="fail", status_code=status_code(response), message=parsed_response)) }
}

# ---------------------------------------------------------------------------
# In-memory validation cache
# Loaded once from MySQL on first use, refreshed every 24 hours.
# Add new networks/protocols via SQL and the cache will pick them up on the
# next restart (or after 24 hours).
# ---------------------------------------------------------------------------
.cache_env <- new.env(parent = emptyenv())

cache_init <- function() {
  tryCatch({
    con <- db_con()
    on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
    networks_df  <- dbGetQuery(con, "SELECT LOWER(name) as name FROM networks")
    protocols_df <- dbGetQuery(con, "SELECT LOWER(name) as name FROM protocols")
    pairs_df     <- dbGetQuery(con, "SELECT LOWER(n.name) as network, p.pair FROM pairs p JOIN networks n ON p.network_id = n.network_id")
    .cache_env$valid_networks  <- networks_df$name
    .cache_env$valid_protocols <- protocols_df$name
    .cache_env$valid_pairs     <- pairs_df
    .cache_env$cache_time      <- Sys.time()
    cat(sprintf("✅ Validation cache loaded: %d networks, %d protocols, %d pairs\n",
                length(.cache_env$valid_networks),
                length(.cache_env$valid_protocols),
                nrow(.cache_env$valid_pairs)))
  }, error = function(e) {
    cat("⚠️  Validation cache init failed:", e$message, "\n")
    # Fallback to hardcoded list so the gateway keeps running
    .cache_env$valid_networks  <- c("optimism", "polygon", "arbitrum", "base", "ethereum", "mainnet", "hyperliquid")
    .cache_env$valid_protocols <- c("dhedge")
    .cache_env$valid_pairs     <- data.frame(network = character(0), pair = character(0), stringsAsFactors = FALSE)
    .cache_env$cache_time      <- Sys.time()
  })
}

cache_refresh_if_needed <- function() {
  if (is.null(.cache_env$cache_time) ||
      difftime(Sys.time(), .cache_env$cache_time, units = "hours") > 24) {
    cache_init()
  }
}

is_valid_network <- function(network) {
  network <- gsub("[ ']", "", network)
  cache_refresh_if_needed()
  return(tolower(network) %in% .cache_env$valid_networks)
}

is_valid_protocol <- function(protocol) {
  protocol <- gsub("[ ']", "", protocol)
  cache_refresh_if_needed()
  return(tolower(protocol) %in% .cache_env$valid_protocols)
}

is_valid_pair <- function(network, pair) {
  network <- gsub("[ ']", "", network)
  pair    <- gsub("[ ']", "", pair)
  cache_refresh_if_needed()
  return(any(.cache_env$valid_pairs$network == tolower(network) &
             .cache_env$valid_pairs$pair    == pair))
}

basic_check <- function(network, protocol=NULL, apiKey, pool=NULL, wallet=NULL, pair=NULL, trader=NULL, ip=NULL) {
  network <- tolower(network);
  if (!is.null(protocol)) protocol <- tolower(protocol)
  if (!is_valid_network(network)) return(list(status="fail", status_code="1000", message="Unrecognized network"))
  if (!is_valid_protocol(protocol)) return(list(status="fail", status_code="1001", message="Unrecognized protocol"))
  if (!isValidAPIKey(apiKey)) return(list(status="fail", status= "1002", message="Invalid API Key"))
  if (!is.null(pair)) {
          if (!is_valid_pair(network, pair)) return(list(status="fail", status_code="1003", message="Invalid Pair"))
  }
  if (!is.null(pool)) {
        if (!isValidEthereumAddress(pool)) return(list(status="fail", status_code="1004", message="Invalid Pool Address"))
  }
  if (!is.null(wallet)) {
        if (!isValidEthereumAddress(wallet)) return(list(status="fail", status_code="1005", message="Invalid Ethereum Address"))
  }
  if (!is.null(trader)) {
        if (!isValidTrader(protocol=protocol,pool=pool,trader=trader)) return(list(status="fail", status_code="1006", message="The trader wallet is not configured as a trader in the specified pool"))
  }
  return(list(status="success"))
}
listToDiscord <- function(x) {
  paste0("```", paste0(names(x), ": ", unlist(x), collapse = "\n"), "```")
}
api_check = function(apiKey,protocol,pool,wallet=NULL,network=NULL) {
        if (is.null(wallet)) {
		url <- paste0(ep,"getWallet?apiKey=",apiKey)
        	response <- GET(url)
        	response_content <- content(response, "text")
        	parsed_response <- fromJSON(response_content)
        	if (status_code(response) == 200) { wallet <- parsed_response$msg }
        	else { return(list(status="fail",status_code=status_code(response),message=parsed_response)) }
	}
	if (!isValidTrader(protocol,pool,wallet)) { return(list(status="fail", status_code="1006", message="The trader wallet is not configured as a trader in the specified pool")) }

	#Change this to another provider etherscan is off!

	#if (!is.null(wallet) && !is.null(network)) {
	#	gasBalance=getGasBalances(wallet,network)
	#	if (gasBalance == 0) return(list(status="fail",status_code=500,message="Your wallet gas token balance is 0, please send at least $1 USD worth of gas before linking the wallet."))
	#}
	return(list(status="success",status_code=200,message="API Check Passed"))
}
is_signature_format_valid <- function(sig) {
  if (!is.character(sig) || length(sig) != 1 || is.na(sig)) return(FALSE)
  # EOA: exactly 65 bytes (130 hex). Safe packed: N*65 bytes (N>=1 owners).
  # Also allow contract-sig format which may have extra data bytes.
  if (!grepl("^0x[0-9a-fA-F]{130,}$", sig)) return(FALSE)
  return(TRUE)
}
signature_message="Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations."

verifySignature <- function(message=signature_message, signature, manager_address, network=NULL) {
  # Create JSON body — network is optional, only needed for Safe multisig (EIP-1271)
  body <- list(
    message = message,
    signature = signature,
    expectedAddress = manager_address
  )
  if (!is.null(network) && nchar(network) > 0) body$network <- tolower(network)

  # Make POST request
  response <- POST(
    url = paste0(ep, "verifySignature"),
    body = body,
    encode = "json",
    content_type_json()
  )

  # Parse response
  response_content <- content(response, as = "text", encoding = "UTF-8")
  parsed <- fromJSON(response_content)

  # Check result
  if (status_code(response) == 200 && parsed$status == "success") {
    return(parsed$isValid)
  } else {
    warning(paste("Verification failed:", parsed$msg))
    return(FALSE)
  }
}

#Testing
#manager="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5"
#signature="0xbb386c636b399080d73841476fed1bf353383ff5b30967f7e22ba977f116846e22266a6281a8ea01768c119b9fd97cbf6d5b47692f1bad2ea149f049fee5cad01c"
#is_signature_format_valid(signature)
#verifySignature(signature_message,signature=signature,manager=manager)
