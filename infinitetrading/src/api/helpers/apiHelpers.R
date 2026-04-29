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

is_valid_network <- function(network) {
  network <- gsub("[ ']", "", network)
  conn <- db_con()
  query <- "SELECT COUNT(*) as count FROM networks WHERE name = LOWER(?)"
  result <- dbGetQuery(conn, query, params = list(network))
  dbDisconnect(conn)
  return(result$count > 0)
}

is_valid_protocol <- function(protocol) {
  protocol <- gsub("[ ']", "", protocol)
  conn <- db_con()
  query <- "SELECT COUNT(*) as count FROM protocols WHERE name = LOWER(?)"
  result <- dbGetQuery(conn, query, params = list(protocol))
  dbDisconnect(conn)
  return(result$count > 0)
}

is_valid_pair <- function(network, pair) {
  network <- gsub("[ ']", "", network)
  pair <- gsub("[ ']", "", pair)
  conn <- db_con()
  query <- "SELECT COUNT(*) as count FROM pairs p JOIN networks n ON p.network_id = n.network_id WHERE n.name = LOWER(?) AND p.pair = ?"
  result <- dbGetQuery(conn, query, params = list(network, pair))
  dbDisconnect(conn)
  return(result$count > 0)
}

basic_check <- function(network, protocol=NULL, apiKey,pool= NULL, wallet = NULL,pair= NULL,trader=NULL) {
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
  if (!is.character(sig)) return(FALSE)
  if (!grepl("^0x[0-9a-fA-F]{130}$", sig)) return(FALSE)
  return(TRUE)
}
signature_message="Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations."

verifySignature <- function(message=signature_message, signature, manager_address) {
  # Create JSON body
  body <- list(
    message = message,
    signature = signature,
    expectedAddress = manager_address
  )

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
