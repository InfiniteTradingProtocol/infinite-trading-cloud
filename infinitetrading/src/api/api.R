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

poolCompositionHandler <- function(pool, network, protocol) { pool_comp(pool,network,protocol) }
pr$handle("GET", "/poolComposition", poolCompositionHandler, serializer = serializer_json(), comment = "
	  # @summary Get Pool Composition
	  # @description Retrieves the composition of a specified pool on a given network and protocol.
	  # @tag Get pool composition
	  # @param pool query string true 'The pool identifier or name.'
	  # @param network query string true 'The network where the pool is located (e.g., \"ethereum\", \"polygon\", \"arbitrum\", \"base\").'
	  # @param protocol query string true 'The protocol used by the pool (e.g., \"dhedge\", \"defund\").'
	  # @response 200 Successful operation
	  # @response 400 Invalid request parameters
	  ")

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

createWalletHandler = function() {
	response <- POST(paste0(ep,"createWallet"))
	response_content <- content(response, "text")
	parsed_response <- fromJSON(response_content)
	if (status_code(response) == 200) {
		address <- parsed_response$address
		private_key <- parsed_response$privateKey
		print("New Gas Wallet Succesfully Created")
		#cat("Address: ", address, "\n")
		#cat("Private Key: ", private_key, "\n")
	} else { print(paste("Failed with status", status_code(response))) }
	private_key <- remove_0x_prefix(private_key)
        api_key <- secure_encrypt(private_key, hexmode = TRUE)
  	decrypted_api_key <- add_0x_prefix(secure_decrypt(api_key))
        encrypted_api_key <- secure_encrypt(api_key,hexmode=TRUE)
        # Print results
        #print(paste("Encrypted private key (API KEY):", api_key))
        #print(paste("Decrypted private key:", decrypted_api_key))
        #print(paste("Encrypted API key:", encrypted_api_key))
  	pk <- add_0x_prefix(decrypt_twice(encrypted_api_key))
  	#print(paste0("Private key from Encrypted API key:", pk))
	res = c()
	# add here checks if the values are correct to return this, otherwise return the error.
	res$status = 200
	result <- list(status="success",status_code=200,address = address, privateKey = private_key, apiKey = api_key)
}

pr$handle("POST","/createWallet", createWalletHandler, serializer = serializer_json())

#========================================================================================================================

approveHandler = function(network, protocol, pool, asset, platform, apiKey, short) {
    res = c()
    if (asset == "BTC") { asset = "WBTC" }
    else if (asset == "USD") { asset = "USDC" }
    else if (asset == "ETH") { asset = "WETH" }
    else if (asset == "MATIC" || asset == "POL") { asset = "WMATIC" }

    if (!isValidApiKey(network, protocol, pool, apiKey)) {
        res = c(); res$status <- 401;
        return(list(status="fail", status_code=401, message="The API Key is invalid or it has not linked to the specified pool"))
    }
    asset_contract = get_contract(asset,network)
    # Get contract address and symbol
    if (isValidEthereumAddress(asset)) { symbol = get_symbol(asset, network) }
    else { asset_contract = get_contract(asset, network); symbol = asset }
    print("api approve invoked")
    print(paste("asset:",asset,"asset_contract:", asset_contract, "symbol:",symbol))
    if (is.null(asset_contract)) {
        return(list(status="fail", status_code=400, message="Unsupported asset for the specified network and protocol"))
    }

    # ✅ Pool composition check
    comp <- pool_comp(pool=pool, network=network, protocol=protocol)
    #if (length(comp) == 0 || !(tolower(asset_contract) %in% tolower(comp[,"asset"]))) {
    #    return(list(status="fail", status_code=400, message=paste0("Enable ", symbol, " on the dHEDGE vault first.")))
    #}

    if (grepl("BULL", symbol, ignore.case = TRUE) || grepl("BEAR", symbol, ignore.case = TRUE)) {
        platform <- "toros"
    }

    url = paste0(ep, "approve?network=", network, "&apiKey=", apiKey, "&pool=", pool, "&platform=", platform)
    print(paste0("approving asset: ", asset, " / contract: ", asset_contract))
    print(paste0("approve url: ", url, " / asset contract: ", asset_contract))

    # ---- async + retry (minimal change) ----
    future_promise({
        # up to 3 attempts with small backoff; don't retry on 4xx
        attempt_max <- 3
        http_res <- NULL
        for (i in 1:attempt_max) {
            http_res <- try(httr::POST(url, body = list(asset = asset_contract), encode = "json", httr::timeout(60)), silent = TRUE)
            if (!inherits(http_res, "try-error")) {
                sc <- httr::status_code(http_res)
                if (!is.na(sc) && sc < 500) break  # succeed or non-retriable (e.g., 4xx)
            }
            # backoff: 0.5s, 1s (cap small to keep behavior snappy)
            Sys.sleep(min(0.5 * 2^(i - 1), 1.0))
        }

        if (inherits(http_res, "try-error") || is.null(http_res)) {
            # network/hard failure -> keep your fail structure
            return(list(status="fail", status_code=400, message="Approve failed, try again or contact support"))
        }

        response_content <- httr::content(http_res, "text", encoding = "UTF-8")
        parsed_response <- tryCatch(jsonlite::fromJSON(response_content), error = function(e) list(msg = response_content))

        if (httr::status_code(http_res) == 200) {
            if (!is.null(parsed_response$msg)) print(parsed_response$msg)
            res$status <<- 200
            list(status="success", status_code=200, message="Asset approved")
        } else {
            if (!is.null(parsed_response$msg)) print(parsed_response$msg)
            #here i have to detect this: insufficient funds for gas * price + value for insufficient gas
	    #print(paste("Failed with status", httr::status_code(http_res)))
            res$status <<- httr::status_code(http_res)
            list(status="fail", status_code=400, message="Approve failed, try again or contact support")
        }
    })
}

pr$handle("POST","/approve", approveHandler, serializer = serializer_json())

#========================================================================================================================

getApiKeyHandler = function(privateKey) {
        privateKey <- remove_0x_prefix(privateKey)
        apiKey <- secure_encrypt(privateKey, hexmode = TRUE)
        result <- list(status="success",status_code=200,apiKey = apiKey)
}
pr$handle("POST","/getApiKey", getApiKeyHandler, serializer = serializer_json())

#========================================================================================================================

getWallet = function(apiKey) {
	url <- paste0(ep,"getWallet?apiKey=",apiKey)
        response <- GET(url); response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
        if (status_code(response) == 200) { return(parsed_response$msg) } 
	else { return(list(status="fail",status_code=status_code(response),message=parsed_response)) }
}


#========================================================================================================================

linkGasWalletHandler = function(network,protocol,pool,apiKey) { 
	wallet = getWallet(apiKey)
	response = api_check(apiKey,protocol,pool,wallet,network)
	if (response$status_code == 200) { linkGasWallet(network,protocol,wallet,pool,apiKey) }
	else { response }
}

pr$handle("POST","/linkGasWallet", linkGasWalletHandler, serializer = serializer_json())

#========================================================================================================================

getGasBalanceHandler <- function(network, apiKey, USD = TRUE) {
  networks <- c("ethereum", "polygon", "optimism", "arbitrum", "base")

  if (network != "all" && !is_valid_network(network)) {
    return(list(status = "fail", status_code = "1000", message = "Unrecognized network"))
  }

  if (!isValidAPIKey(apiKey)) {
    return(list(status = "fail", status_code = 401, message = "The API Key is invalid"))
  }

  wallet <- getWallet(apiKey)
  USD <- isTRUE(USD)
  structured <- (network == "all")

  gasBalance <- getGasBalances(wallet, network, structured)

  if (network == "all") {
    result <- list()
    for (entry in gasBalance) {
      net <- entry$network
      address <- entry$wallet
      balance <- entry$balance
      price <- 1

      if (USD) {
        pair <- if (net == "polygon") "POL-USD" else "ETH-USD"
        price <- suppressWarnings(as.numeric(getTicks(exchange = "coinbase", pair = pair)))
        if (is.na(price)) price <- 0
      }

      result[[length(result) + 1]] <- list(
        network = net,
        address = address,
        usd_balance = round(balance * price, 6)
      )
    }
    return(list(status = "success", status_code = 200, message = result))
  }

  # Single-network case (not "all")
  price <- 1
  if (USD) {
    pair <- if (network == "polygon") "POL-USD" else "ETH-USD"
    price <- suppressWarnings(as.numeric(getTicks(exchange = "coinbase", pair = pair)))
    if (is.na(price)) price <- 0
  }

  return(list(status = "success", status_code = 200, message = gasBalance * price))
}

pr$handle("POST","/getGasBalance", getGasBalanceHandler, serializer = serializer_json())

#========================================================================================================================

getAllGasBalanceHandler <- function(network, manager, USD = TRUE,signature=NULL) {
  if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
  if (network != "all" && !is_valid_network(network)) {
    return(list(status = "fail", status_code = "1000", message = "Unrecognized network"))
  }

  if (!isValidEthereumAddress(manager)) {
    return(list(status = "fail", status_code = 401, message = "The manager address is invalid"))
  }
  
  wallet_df <- getAssociatedGasWallets(manager, noKey = TRUE)

  # Extract just the addresses into a character vector
  addresses <- wallet_df$wallet

  if (length(addresses) == 0) {
    return(list(status = "success", status_code = 200, message = list()))
  }
  result <- list()

  process_network <- function(net) {
    balances <- getGasBalances(addresses, net, structured = TRUE)

    if (USD) {
      pair <- if (net == "polygon") "POL-USD" else "ETH-USD"
      price <- suppressWarnings(as.numeric(getTicks(exchange = "coinbase", pair = pair)))
      if (is.na(price)) price <- 1
    }

    for (entry in balances) {
      result[[length(result) + 1]] <<- list(
        network = net,
        address = entry$wallet,
	balance = entry$balance,
        usd_balance = round(entry$balance * price, 2)
      )
    }
  }

  if (network == "all") {
    for (net in networks) process_network(net)
  } else {
    process_network(network)
  }

  return(list(status = "success", status_code = 200, message = result))
}

pr$handle("GET","/getAllGasBalance", getAllGasBalanceHandler, serializer = serializer_json())

#========================================================================================================================

getAllBotsHandler <- function(manager, protocol = "dhedge",signature=NULL) {
  if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
  if (!isValidEthereumAddress(manager)) {
    return(list(status = "fail", status_code = 401, message = "The manager address is invalid"))
  }

  bots_result <- tryCatch({
    getBots(manager, protocol)
  }, error = function(e) {
    return(list(status = "fail", status_code = 500, message = paste("Internal error:", e$message)))
  })

  # If getBots returned a full response already (with status/status_code), return it
  if (!is.null(bots_result$status)) {
    return(bots_result)
  }

  # If getBots returned only a list of bot entries
  return(list(
    status = "success",
    status_code = 200,
    bots = bots_result
  ))
}

pr$handle("POST","/getAllBots", getAllBotsHandler, serializer = serializer_json())

#========================================================================================================================

unlinkGasWalletHandler = function(network,protocol,pool,apiKey) {
	if (isValidApiKey(network=network,protocol=protocol,pool=pool,apiKey=apiKey)) { unlinkGasWallet(network,protocol,pool) }
	else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}
pr$handle("POST","/unlinkGasWallet", unlinkGasWalletHandler, serializer = serializer_json())

##########

setSideHandler = function(apiKey,protocol,pool,network,pair,side,threshold,max_usd,slippage,share,platform,lending=FALSE) {
	if (is.null(lending) || !is.logical(lending)) { lending = FALSE }
	if (!isValidApiKey(network,protocol,pool,apiKey)) { return(list(status="fail",status_code=401,message="Invalid API key")) }
	else if (side == "short") {
	       	if (!(network %in% short_networks)) { return(list(status="fail",status_code=401,message="Shorting is not allowed on the specified network")) }
		else { 
			#composition = pool_composition(pool_comp(pool,network,protocol))
			#check if is_btc or is_eth
			#if check if btcbear1x or ethbear1x is enabled else return error
			#check if intermediary asset is enabled else return error
		}
	}
	res = setSide(protocol=protocol,pool=pool,network=network,pair=pair,side=side,threshold=threshold,slippage=slippage,max_usd=max_usd,share=share,platform=platform,lending=lending)
	print(paste0("/setSide: ",res))
	
	executeTrades_res = tryCatch({executeTrades(pool=pool, pair=pair, side=side, share=as.numeric(share),threshold=as.numeric(threshold), slippage=as.numeric(slippage), apiKey=apiKey,max_usd=as.numeric(max_usd), composition=NULL,platform=platform, protocol=protocol, network=network)
	},error = function(e) { e$message })
	if (lending) { 
		print("lending enabled")
		#executeLendUnlend()
		#Should I need to send lending=TRUE to execute trades to allow the lending of the asset ? 
		#It should verify if the whole side is on its correct side to then LEND.
		#It should verify before buying if there is an asset in LENDING to UNLEND.
	}
	print(paste0("/setSide: executeTrades response:",executeTrades_res))

	return(res)
}

pr$handle("POST","/setSide",setSideHandler, serializer = serializer_json())

#========================================================================================================================

getSideHandler = function(apiKey,protocol,pool,network) {
        if (isValidApiKey(network,protocol,pool,apiKey)) { getSide(protocol=protocol,pool=pool,network=network) }
        else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}
pr$handle("POST","/getSide",getSideHandler, serializer = serializer_json())


#========================================================================================================================

deleteBotHandler = function(apiKey, protocol, pool, network) {
    if (isValidApiKey(network, protocol, pool, apiKey)) {
        deleteBot(protocol = protocol, pool = pool, network = network)
    } else {
        res = c()
        res$status <- 401
        list(status = "fail", status_code = 401, message = "Invalid API key")
    }
}
pr$handle("POST", "/deleteBot", deleteBotHandler, serializer = serializer_json())

#========================================================================================================================

getSupportedAssetsHandler = function(apiKey,network) { getSupportedAssets(network) }
pr$handle("POST","/getSupportedAssets",getSupportedAssetsHandler, serializer = serializer_json())

#========================================================================================================================

getCandlesHandler = function(exchange,timeframe,pair,apiKey,bars_back) { 
	if (apiKey=="frontend" || apiKey =="vault42") { return(getCandles(exchange=exchange,timeframe=timeframe,pair=pair,bars_back=bars_back)) }
	else { list(status="fail",status_code=401,message="Invalid API Key") }
}
pr$handle("POST","/getCandles",getCandlesHandler, serializer = serializer_json())

#========================================================================================================================

getTicksHandler = function(exchange,pair,apiKey) {
        if (apiKey=="frontend") { return(getTicks(exchange=exchange,pair=pair)) }
        else { list(status="fail",status_code=401,message="Invalid API Key") }
}
pr$handle("POST","/getTicks",getTicksHandler, serializer = serializer_json())

#========================================================================================================================

getTotalYieldHandler = function(pool,apiKey) {
	if (apiKey=="frontend") return(getTotalYield(pool))
        list(status="fail",status_code=401,message="Invalid API Key") 
}
pr$handle("GET","/getTotalYield",getTotalYieldHandler, serializer = serializer_json())

#========================================================================================================================

getEstimatedAnualYieldHandler = function(pool,apiKey) {
        if (apiKey=="frontend") return(getEstimatedAnualYield(pool))
        list(status="fail",status_code=401,message="Invalid API Key")
}
pr$handle("GET","/getEstimatedAnualYield",getEstimatedAnualYieldHandler, serializer = serializer_json())

#========================================================================================================================

getAllYieldsHandler = function(apiKey) {
        if (apiKey=="frontend") return(getAllYields())
        list(status="fail",status_code=401,message="Invalid API Key")
}
pr$handle("GET","/getAllYields",getAllYieldsHandler, serializer = serializer_json())


#========================================================================================================================

getGasWalletPoolsHandler = function(apiKey,protocol,network,wallet) {
	protocol = tolower(protocol); network=tolower(network); wallet = tolower(wallet);
	if (network != "all") { 
		if (!is_valid_network(network)) return(list(status="fail", status_code="1000", message="Unrecognized network"))
	}
	if (protocol != "dhedge") {
		if (!is_valid_protocol(protocol)) return(list(status="fail",status_code=401,message="Unrecognized protocol"))
	}
	if (apiKey=="frontend") return(getWalletPools(protocol, network, wallet))
        list(status="fail",status_code=401,message="Invalid API Key")
}

pr$handle("GET","/getGasWalletPools",getGasWalletPoolsHandler, serializer = serializer_json())

#========================================================================================================================

associateGasWalletHandler <- function(apiKey,manager,label,signature=NULL) {
	if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
        label = substr(label, 1, min(42, nchar(label)))
	wallet = getWallet(apiKey)
        if (!isValidAPIKey(apiKey)) return(list(status="fail",status_code=401,message="The API Key is invalid"))
        if (!isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(associateGasWallet(wallet,manager,label,apiKey))
}

pr$handle("GET","/associateGasWallet",associateGasWalletHandler,serializer = serializer_json())


#========================================================================================================================

#I need to add here the signature! 
#Remove the 'frontend' api key needed.
#Return the API Keys.

getAssociatedGasWalletsHandler <- function(apiKey=NULL,manager=NULL,signature=NULL) {
        if (is.null(apiKey) || is.null(manager) || is.null(signature)) {
                return(list(status="fail",status_code=400,message="Missing required parameters: apiKey, manager, or signature"))
        }
        if (apiKey != "frontend") return(list(status="fail",status_code=401,message="Invalid API Key"))
        if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
	if (!isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(getAssociatedGasWallets(manager))
}

pr$handle("POST","/getAssociatedGasWallets",getAssociatedGasWalletsHandler,serializer = serializer_json())

#========================================================================================================================

#========================================================================================================================

deassociateGasWalletHandler <- function(apiKey,wallet, manager,signature) {
	if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }    
 	if (!isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(deassociateGasWallet(wallet,manager))
}

pr$handle("GET","/deassociateGasWallet",deassociateGasWalletHandler,serializer = serializer_json())

#========================================================================================================================

mintFeesHandler = function(pool,apiKey,network,protocol) {
	response = api_check(apiKey=apiKey,protocol=protocol,pool=pool,wallet=NULL,network=network)
	if (response$status_code == 200) { 
		url = paste0(ep,"mintManagerFee?pool=",pool,"&network=",network,"&apiKey=",apiKey,"&protocol=",protocol)
		# Send the GET request to the server
		response <- GET(url)
		# Check the status code of the response
		if (status_code(response) == 200) { return (response) }
		else { res = c(); res$status <- status_code(response); list(status="fail",status_code=status_code(response),message=response) }
	}
       return(res)
}
pr$handle("POST","/mintFees",mintFeesHandler, serializer = serializer_json())

#========================================================================================================================

vaultTradeHandler <- function(network,pool,protocol,platform,apiKey,from, to, slippage, share, amount=NA) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
       	if (is_toros(from) || is_toros(to)) { platform="toros" }  
	#Basic security check
	check = api_check(apiKey=apiKey,protocol=protocol,pool=pool,wallet=NULL,network=network)
        if (check$status_code != 200) return(check)

        if (from == "BTC") { from = "WBTC" }
	else if (to == "BTC") { to = "BTC" }
        else if (from == "USD") { from = "USDC" }
        else if (to == "USD") { to = "USDC" }
        else if (from =="ETH") { from = "WETH" }
        else if (from == "MATIC" || from=="POL") { from = "WMATIC" }
        else if (to =="ETH") { to = "WETH" }
        else if (to == "MATIC" || to=="POL") { to = "WMATIC" }
        if (!isValidApiKey(network,protocol,pool,apiKey)) {
                res = c(); res$status <- 401;
                return(list(status="fail",status_code=401,message="The API Key is invalid or it has not linked to the specified pool"))
        }
        
	#Check from asset

	if (isValidEthereumAddress(from)) { from_contract = from }
        else { from_contract = getContractHandler(from,network) }
	
	#Check to asset

	if (isValidEthereumAddress(to)) { to_contract = to }
        else { to_contract = getContractHandler(to,network) }

        
	if (is.null(from_contract)) return(list(status="fail",status_code=400,message="Unsupported 'from' asset for the specified network and protocol")) 
	if (is.null(to_contract)) return(list(status="fail",status_code=400,message="Unsupported 'to' asset for the specified network and protocol")) 

        slippage = as.numeric(slippage); share = as.numeric(share);
        url <- paste0(ep,"trade?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&from=",from_contract,"&to=",to_contract,"&slippage=",slippage,"&platform=",platform)
	if (is_toros(from)) { url = paste0(url,"&withdrawal=true") }
	ignore_share=FALSE
	if (!is.na(amount)) {
		if (amount == "NA") { amount = NA }
                amount = as.numeric(amount)
                if (is.na(amount)) { return(list(status="fail",status_code=400,message="The specified amount parameter is not numeric")) }
                else {
                        if (amount > 0) {
                                decimals = get_decimals(from)
                                amount = floor(amount*(10^decimals))
				ignore_share=TRUE
                                url = paste0(url,"&amount=",amount)
                        }
                        else { return(list(status="fail",status_code=400,message="The speficied amount parameter must be a number > 0 or NA")) }
                }
        }
	else if (!is.na(share) && !ignore_share) {
                if (share >=1 && share <= 100) { share = round(share); url = paste0(url,"&share=",share) }
                else { return(list(status="fail",status_code=400,message="The 'share' parameter is not an integer between [1,100]")) }
        } else { return(list(status="fail",status_code=400,message="The 'share' parameter is not an integer between [1,100]")) }
	
	response <- GET(url);
	content_response = content(response,"text");
	parsed_response <- fromJSON(content_response)
        
        print(paste0("trade url: ",url," response: ",content_response))
	print(parsed_response); 
        res = c(); res$status = status_code(response)
	if (status_code(response) == 200) {
                result <- list(status="success",status_code=200,message="trade executed")
        } else {
                print(paste("Failed with status", status_code(response)))
                result <- list(status="fail",status_code=status_code(response),message=paste0("trade failed: ",parsed_response$msg))
        }
        masked_api = mask_api(apiKey)
        msg = paste0("vaultTrade invoked by apiKey: ",masked_api, " / pool: ",pool," / protocol: ", protocol, " / network: ",network,"/ from: ", from,"/ to: ",to," / amount: ",amount," / slippapge: ",slippage," / share: ",share," / platform: ",platform," / status_code: ",result$status_code," / message: ",result$message)
        print(msg)
        #discord(msg=msg,channel="#api-logs",db=FALSE)
        send_telegram_text(msg)
	return(result)
}
pr$handle("GET","/vaultTrade",vaultTradeHandler, serializer = serializer_json())

#========================================================================================================================

repayHandler <- function(apiKey, protocol, pool, network, asset, share, amount = NULL, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    url <- paste0(ep, "repay?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,
                  "&network=", network, "&asset=", asset, "&platform=", platform)

    share <- as.numeric(share)
    if (!is.na(share) && is.numeric(share)) {
        if (share >= 1 && share <= 100) {
            share <- round(share)
            url <- paste0(url, "&share=", share)
        } else {
            res <- list(status = "fail", status_code = 1007, message = "error: share must be in [1,100]")
        }
    } else if (!is.null(share)) {
        res <- list(status = "fail", status_code = 1007, message = "error: share must be numeric [1,100]")
    }

    if (!is.null(amount)) {
        if (!is.numeric(amount) || is.na(amount)) {
            res <- list(status = "fail", error_code = 1011, message = "The specified amount parameter is not numeric")
        } else if (amount <= 0) {
            res <- list(status = "fail", error_code = 1009, message = "The specified amount must be > 0")
        } else {
            amount <- round(amount, 2)
            url <- paste0(url, "&amount=", amount)
        }
    }

    if (res$status == "success") {
        response <- POST(url)
        content_response <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

        if (status_code(response) == 200) return(response)
        res <- list(status = "fail", status_code = status_code(response), message = content_response)
    }

    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " repay invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  " / share: ", share, " / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    send_telegram_text(msg)
    #discord(msg = msg, channel = "#api-logs", db = FALSE)

    return(res)
}
pr$handle("POST","/repay",repayHandler, serializer = serializer_json())

#========================================================================================================================

borrowHandler <- function(apiKey, protocol, pool, network, asset, share=NULL, amount, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    url <- paste0(ep, "borrow?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,
                  "&network=", network, "&asset=", asset, "&platform=", platform)

    #share <- as.numeric(share)
    #if (!is.na(share) && is.numeric(share)) {
    #    if (share >= 1 && share <= 100) {
    #        share <- round(share)
    #        url <- paste0(url, "&share=", share)
    #    } else {
    #        res <- list(status = "fail", status_code = 1007, message = "error: share must be in [1,100]")
    #    }
    #} else if (!is.null(share)) {
    #    res <- list(status = "fail", status_code = 1007, message = "error: share must be numeric [1,100]")
    #}

    if (!is.null(amount)) {
        if (!is.numeric(amount) || is.na(amount)) {
            res <- list(status = "fail", error_code = 1011, message = "The specified amount parameter is not numeric")
        } else if (amount <= 0) {
            res <- list(status = "fail", error_code = 1009, message = "The specified amount must be > 0")
        } else {
            amount <- round(amount, 2)
            url <- paste0(url, "&amount=", amount)
        }
    }

    if (res$status == "success") {
	response <- POST(url)
        content_response <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

        if (status_code(response) == 200) return(response)
        res <- list(status = "fail", status_code = status_code(response), message = content_response)
    }

    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " borrow invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  " / share: ", share, " / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    send_telegram_text(msg)
    #discord(msg = msg, channel = "#api-logs", db = FALSE)

    return(res)
}

pr$handle("POST", "/borrow", borrowHandler, serializer = serializer_json())

#========================================================================================================================

lendHandler <- function(apiKey, protocol, pool, network, asset, share, amount = NULL, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    print(get_contract(asset,network))
    url <- paste0(ep, "lend?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,"&network=", network, "&asset=", get_contract(asset,network), "&platform=", platform)

    share <- as.numeric(share)
    if (!is.na(share) && is.numeric(share)) {
        if (share > 0 && share <= 100) { share <- round(share,2); url <- paste0(url, "&share=", share) } 
	else { res <- list(status = "fail", status_code = 1007, message = "error: share must be in (0,100]") }
    } 
    else if (!is.null(share)) { res <- list(status = "fail", status_code = 1007, message = "error: share must be numeric (0,100]") }
    #if (!is.null(amount)) {
    #    amount = as.numeric(amount)
    #        if (is.na(amount)) { res <- list(status = "fail", status_code = 1011, message = "The specified amount parameter is not numeric") } 
    #	    else if (amount <= 0) { res <- list(status = "fail", status_code = 1009, message = "The specified amount must be > 0") }
    #	    else { amount <- round(amount, 2); url <- paste0(url, "&amount=", amount) }
    #} 
    if (res$status == "success") {
    	print(paste0("All check passed for lendHandler, invoking express:", url))
    	response <- POST(url)
    	txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

    	if (status_code(response) == 200) {
        	parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
        	# Always return a plain R list (never an httr response)
        	return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
    	}
    	res <- list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt))
    }
    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " lend invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  " / share: ", share, 
		  #" / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    send_telegram_text(msg)
    #discord(msg = msg, channel = "#api-logs", db = FALSE)
    return(res)
}
pr$handle("POST","/lend",lendHandler, serializer = serializer_json())

#========================================================================================================================

unlendHandler <- function(apiKey, protocol, pool, network, asset, share=NULL, amount, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    print(get_contract(asset,network))
    url <- paste0(ep, "unlend?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,"&network=", network, "&asset=", get_contract(asset,network), "&platform=", platform)

    #share <- as.numeric(share)
    #if (!is.null(share) && !is.na(share)) {
    #    if (share > 0 && share <= 100) { share <- round(share,2); url <- paste0(url, "&share=", share) }
    #    else { res <- list(status = "fail", status_code = 1007, message = "error: share must be in (0,100]") }
    #}
    #else if (!is.null(share)) { res <- list(status = "fail", status_code = 1007, message = "error: share must be numeric (0,100]") }
    if (!is.null(amount)) {
       	   amount = as.numeric(amount)
           if (is.na(amount)) { res <- list(status = "fail", status_code = 1011, message = "The specified amount parameter is not numeric") }
           else if (amount <= 0) { res <- list(status = "fail", status_code = 1009, message = "The specified amount must be > 0") }
           else { amount <- round(amount, 2); url <- paste0(url, "&amount=", amount) }
    }
    else { 
    	res <- list(status = "fail", status_code = 400, message = "No amount parameter specified")
    }
    if (res$status == "success") {
        print(paste0("All check passed for unlendHandler, invoking express:", url))
        response <- POST(url)
        txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

        if (status_code(response) == 200) {
                parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
                # Always return a plain R list (never an httr response)
                return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
        }
        res <- list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt))
    }
    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " unlend invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  #" / share: ", share, 
		  " / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    send_telegram_text(msg)
    #discord(msg = msg, channel = "#api-logs", db = FALSE)
    return(res)
}
pr$handle("POST","/unlend",unlendHandler, serializer = serializer_json())

#========================================================================================================================

getHealthFactorHandler <- function(apiKey, protocol, pool, network, platform) {
  protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
  check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)

  if (platform == "aave") platform <- "aavev3"
  pool_composition <- pool_comp(pool, network, protocol)

  if (is.null(pool_composition) || length(pool_composition) == 0) {
    res <- list(status = "fail", status_code = 400, message = "unable to fetch pool composition")
    report_activity("getHealthFactor", apiKey, pool, protocol, network, platform, res$status, res$status_code, res$message)
    return(res)
  }

  platform_contract <- get_contract_from_symbol(symbol = platform, comp = pool_composition)
  if (is.null(platform_contract) || is.na(platform_contract) || platform_contract == "") {
    res <- list(status = "fail", status_code = 400, message = paste0("platform '", platform, "' is not enabled inside the vault"))
    report_activity("getHealthFactor", apiKey, pool, protocol, network, platform, res$status, res$status_code, res$msg)
    return(res)
  }

  if (check$status == "fail") return(check)

  # Call Express (GET) and ALWAYS return parsed JSON (a list)
  url <- paste0(
    ep, "getHealthFactor?&pool=", pool,
    "&network=", network,
    "&platform=", platform,
    "&contractAddress=", platform_contract
  )

  response <- httr::GET(url, httr::accept_json())
  txt <- httr::content(response, "text", encoding = "UTF-8")
  parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)

  # Decide what to log/return
  if (!is.null(parsed)) {
    log_status       <- if (!is.null(parsed$status)) parsed$status else if (httr::status_code(response) == 200) "success" else "fail"
    log_status_code  <- if (!is.null(parsed$status_code)) parsed$status_code else httr::status_code(response)
    log_message      <- if (!is.null(parsed$message)) parsed$message else ""
    report_activity("getHealthFactor", apiKey, pool, protocol, network, platform, log_status, log_status_code, log_message)
    return(parsed)
  } else {
    res <- list(status = "fail", status_code = httr::status_code(response), message = txt)
    report_activity("getHealthFactor", apiKey, pool, protocol, network, platform, res$status, res$status_code, res$message)
    return(res)
  }
}
pr$handle("POST","/getHealthFactor",getHealthFactorHandler, serializer = serializer_json())

#========================================================================================================================

getPoolAaveDataHandler <- function(apiKey, protocol, pool, network) {
  protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform= "AAVEV3"
  check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)

  pool_composition <- pool_comp(pool, network, protocol)

  if (is.null(pool_composition) || length(pool_composition) == 0) {
    res <- list(status = "fail", status_code = 400, message = "unable to fetch pool composition")
    report_activity("getPoolAaveData", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  platform_contract <- get_contract_from_symbol(symbol = "AAVEV3", comp = pool_composition)
  if (is.null(platform_contract) || is.na(platform_contract) || platform_contract == "") {
    res <- list(status = "fail", status_code = 400, message = paste0("platform '", platform, "' is not enabled inside the vault"))
    report_activity("getPoolAaveData", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  if (check$status == "fail") return(check)

  # Call Express (GET) and ALWAYS return parsed JSON (a list)
  url <- paste0(ep, "getPoolAaveData?&pool=", pool,"&network=", network,"&contractAddress=", platform_contract)

  response <- httr::GET(url, httr::accept_json())
  txt <- httr::content(response, "text", encoding = "UTF-8")
  parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)

  # Decide what to log/return
  if (!is.null(parsed)) {
    log_status       <- if (!is.null(parsed$status)) parsed$status else if (httr::status_code(response) == 200) "success" else "fail"
    log_status_code  <- if (!is.null(parsed$status_code)) parsed$status_code else httr::status_code(response)
    log_message      <- if (!is.null(parsed$message)) parsed$message else ""
    report_activity("getPoolAaveData", apiKey, pool, protocol, network, log_status, log_status_code, log_message)
    return(parsed)
  } else {
    res <- list(status = "fail", status_code = httr::status_code(response), message = txt)
    report_activity("getPoolAaveData", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }
}
pr$handle("POST","/getPoolAaveData",getPoolAaveDataHandler, serializer = serializer_json())

#========================================================================================================================

getBorrowedHandler <- function(apiKey, protocol, pool, network,asset) {
  protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); asset=get_contract(asset,network)
  check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)

  pool_composition <- pool_comp(pool, network, protocol)
  if (is.null(pool_composition) || length(pool_composition) == 0) {
    res <- list(status = "fail", status_code = 400, message = "unable to fetch pool composition")
    report_activity("getBorrowed", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  platform_contract <- get_contract_from_symbol(symbol = "AAVEV3", comp = pool_composition)
  if (is.null(platform_contract) || is.na(platform_contract) || platform_contract == "") {
    res <- list(status = "fail", status_code = 400, message = paste0("AAVEV3 is not enabled inside the vault"))
    report_activity("getBorrowed", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  if (check$status == "fail") return(check)

  # Call Express (GET) and ALWAYS return parsed JSON (a list)
  url <- paste0(ep, "getBorrowed?&pool=", pool,"&network=", network,"&contractAddress=", platform_contract,"&asset=",asset)

  response <- httr::GET(url, httr::accept_json())
  txt <- httr::content(response, "text", encoding = "UTF-8")
  parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)

  # Decide what to log/return
  if (!is.null(parsed)) {
    log_status       <- if (!is.null(parsed$status)) parsed$status else if (httr::status_code(response) == 200) "success" else "fail"
    log_status_code  <- if (!is.null(parsed$status_code)) parsed$status_code else httr::status_code(response)
    log_message      <- if (!is.null(parsed$message)) parsed$message else ""
    report_activity("getBorrowed", apiKey, pool, protocol, network, log_status, log_status_code, log_message)
    return(parsed)
  } else {
    res <- list(status = "fail", status_code = httr::status_code(response), message = txt)
    report_activity("getBorrowed", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }
}
pr$handle("POST","/getBorrowed",getBorrowedHandler, serializer = serializer_json())

#========================================================================================================================

getSuppliedHandler <- function(apiKey, protocol, pool, network,asset) {
  protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); asset=get_contract(asset,network)
  check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)

  pool_composition <- pool_comp(pool, network, protocol)
  if (is.null(pool_composition) || length(pool_composition) == 0) {
    res <- list(status = "fail", status_code = 400, message = "unable to fetch pool composition")
    report_activity("getSupplied", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  platform_contract <- get_contract_from_symbol(symbol = "AAVEV3", comp = pool_composition)
  if (is.null(platform_contract) || is.na(platform_contract) || platform_contract == "") {
    res <- list(status = "fail", status_code = 400, message = paste0("'AAVEV3' is not enabled inside the vault"))
    report_activity("getSupplied", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }

  if (check$status == "fail") return(check)

  # Call Express (GET) and ALWAYS return parsed JSON (a list)
  url <- paste0(ep, "getSupplied?&pool=", pool,"&network=", network,"&contractAddress=", platform_contract,"&asset=",asset)

  response <- httr::GET(url, httr::accept_json())
  txt <- httr::content(response, "text", encoding = "UTF-8")
  parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)

  # Decide what to log/return
  if (!is.null(parsed)) {
    log_status       <- if (!is.null(parsed$status)) parsed$status else if (httr::status_code(response) == 200) "success" else "fail"
    log_status_code  <- if (!is.null(parsed$status_code)) parsed$status_code else httr::status_code(response)
    log_message      <- if (!is.null(parsed$message)) parsed$message else ""
    report_activity("getSupplied", apiKey, pool, protocol, network, log_status, log_status_code, log_message)
    return(parsed)
  } else {
    res <- list(status = "fail", status_code = httr::status_code(response), message = txt)
    report_activity("getSupplied", apiKey, pool, protocol, network, res$status, res$status_code, res$message)
    return(res)
  }
}
pr$handle("POST","/getSupplied",getSuppliedHandler, serializer = serializer_json())

#========================================================================================================================
# CEX Trading Endpoints
#========================================================================================================================

source("~/infinitetrading/src/exchanges/cex_encryption_compact.R")

# Register CEX Subaccount
registerCEXSubaccountHandler <- function(manager, gas_wallet_api_key, exchange, subaccount_name, 
                                          cex_api_key, cex_secret, cex_passphrase = "", 
                                          payment_network = "base", settings = "", signature = NULL) {
    tryCatch({
        cat("\n=== CEX REGISTRATION START ===\n")
        cat("Manager:", manager, "\n")
        cat("Exchange:", exchange, "\n")
        cat("Subaccount:", subaccount_name, "\n")
        cat("Payment Network:", payment_network, "\n")
        cat("==============================\n\n")
        
        # Verify signature
        sig_valid <- is_signature_format_valid(signature)
        cat("Signature format valid:", sig_valid, "\n")
        
        if (!isTRUE(sig_valid)) {
            return(list(status = "fail", status_code = 401, message = "Invalid Signature Format"))
        }
        
        verify_result <- verifySignature(signature_message, signature, manager)
        cat("Signature verification result:", verify_result, "\n")
        
        if (!isTRUE(verify_result)) {
            return(list(status = "fail", status_code = 401, message = "Invalid Signature"))
        }
        
        # Validate payment_network
        valid_networks <- c("ethereum", "polygon", "optimism", "arbitrum", "base")
        if (!isTRUE(tolower(payment_network) %in% valid_networks)) {
            return(list(status = "fail", status_code = 400,
                       message = sprintf("Invalid payment_network. Must be one of: %s", 
                                       paste(valid_networks, collapse = ", "))))
        }
        payment_network <- tolower(payment_network)
        
        # Validate gas wallet API key
        if (!isTRUE(isValidAPIKey(gas_wallet_api_key))) {
            return(list(status = "fail", status_code = 400, 
                       message = "Invalid gas wallet API key"))
        }
        
        # Get gas wallet address from API key
        gas_wallet <- getWallet(gas_wallet_api_key)
        if (is.null(gas_wallet) || length(gas_wallet) == 0 || isTRUE(gas_wallet == "")) {
            return(list(status = "fail", status_code = 400, 
                       message = "Unable to retrieve gas wallet from API key"))
        }
        
        # Encrypt gas wallet API key for storage
        encrypted_gas_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        
        # Check gas balance across all networks
        # TODO: Re-enable once getGasBalances is fixed (currently using Etherscan which may not be working)
        # gas_balances <- getGasBalances(gas_wallet, network = "all", structured = TRUE)
        total_gas_usd <- 0
        
        # if (length(gas_balances) > 0) {
        #     for (i in seq_along(gas_balances)) {
        #         entry <- gas_balances[[i]]
        #         net <- entry$network
        #         balance <- entry$balance
        #         
        #         # Ensure balance is numeric
        #         if (is.null(balance) || is.na(balance)) balance <- 0
        #         
        #         # Get price in USD
        #         pair <- if (isTRUE(net == "polygon")) "POL-USD" else "ETH-USD"
        #         price_raw <- suppressWarnings(as.numeric(getTicks(exchange = "coinbase", pair = pair)))
        #         price <- if (is.null(price_raw) || is.na(price_raw)) 0 else price_raw
        #         
        #         gas_usd <- balance * price
        #         if (!is.na(gas_usd) && !is.null(gas_usd)) {
        #             total_gas_usd <- total_gas_usd + gas_usd
        #         }
        #     }
        # }
        
        # Ensure total_gas_usd is never NA or NULL
        if (is.na(total_gas_usd) || is.null(total_gas_usd)) total_gas_usd <- 0
        
        # Temporarily skip gas balance check
        # if (isTRUE(total_gas_usd < CEX_MIN_GAS_BALANCE_USD)) {
        #     return(list(status = "fail", status_code = 400, 
        #                message = sprintf("Insufficient gas balance: $%.2f (minimum: $%.2f)", 
        #                                total_gas_usd, CEX_MIN_GAS_BALANCE_USD)))
        # }
        
        # Detect Coinbase Cloud API Key (organizations/apiKeys format)
        is_coinbase_cloud <- isTRUE(exchange == "coinbase") && 
                             isTRUE(grepl("^organizations/.*/apiKeys/", cex_api_key))
        
        # Validate passphrase requirement
        passphrase_required <- isTRUE(exchange %in% c("okx", "kucoin", "bitget")) ||
                               (isTRUE(exchange == "coinbase") && !isTRUE(is_coinbase_cloud))
        
        if (isTRUE(passphrase_required) && (is.null(cex_passphrase) || length(cex_passphrase) == 0 || isTRUE(cex_passphrase == ""))) {
            return(list(status = "fail", status_code = 400, 
                       message = sprintf("%s requires a passphrase (use legacy API keys or provide passphrase)", exchange)))
        }
        
        # Validate Coinbase Cloud API Key format
        if (isTRUE(is_coinbase_cloud)) {
            if (!isTRUE(grepl("BEGIN EC PRIVATE KEY", cex_secret))) {
                return(list(status = "fail", status_code = 400,
                           message = "Invalid EC private key format. Must be PEM format with BEGIN/END markers"))
            }
        }
        
        # Encrypt CEX credentials
        encrypted_api_key <- encrypt_cex_credential(cex_api_key)
        encrypted_secret <- encrypt_cex_credential(cex_secret)
        encrypted_passphrase <- if (!is.null(cex_passphrase) && length(cex_passphrase) > 0 && isTRUE(cex_passphrase != "")) encrypt_cex_credential(cex_passphrase) else NULL
        
        if (is.null(encrypted_api_key) || is.null(encrypted_secret)) {
            return(list(status = "fail", status_code = 500, message = "Failed to encrypt CEX credentials"))
        }
        
        settings_json <- if (!is.null(settings) && length(settings) > 0 && isTRUE(settings != "")) settings else NULL
        
        # Check for existing subaccount
        existing <- db_query(sprintf(
            "SELECT id FROM cex_subaccounts 
             WHERE manager_wallet = '%s' AND exchange = '%s' AND subaccount_name = '%s'",
            tolower(manager), exchange, subaccount_name
        ))
        
        if (nrow(existing) > 0) {
            return(list(status = "fail", status_code = 400,
                       message = sprintf("Subaccount '%s' already exists on %s", 
                                       subaccount_name, exchange)))
        }
        
        # Insert new subaccount
        passphrase_value <- if (is.null(encrypted_passphrase) || length(encrypted_passphrase) == 0) {
            "NULL"
        } else {
            paste0("'", encrypted_passphrase, "'")
        }
        
        settings_value <- if (is.null(settings_json) || length(settings_json) == 0) {
            "NULL"
        } else {
            paste0("'", gsub("'", "''", settings_json), "'")
        }
        
        query <- sprintf(
            "INSERT INTO cex_subaccounts 
            (manager_wallet, gas_wallet, encrypted_gas_wallet_api_key, payment_network, exchange, subaccount_name,
             cex_api_key_encrypted, cex_secret_encrypted, cex_passphrase_encrypted, 
             settings, is_active, gas_balance_usd, last_gas_check)
            VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', %s, %s, TRUE, %.2f, NOW())",
            tolower(manager), tolower(gas_wallet), encrypted_gas_key, payment_network, exchange, subaccount_name, 
            encrypted_api_key, encrypted_secret,
            passphrase_value,
            settings_value,
            total_gas_usd
        )
        
        cat("\n=== CEX REGISTRATION DEBUG ===\n")
        cat("Query:", query, "\n")
        cat("Manager:", manager, "\n")
        cat("Gas Wallet:", gas_wallet, "\n")
        cat("Payment Network:", payment_network, "\n")
        cat("Exchange:", exchange, "\n")
        cat("Subaccount Name:", subaccount_name, "\n")
        cat("==============================\n\n")
        
        db_execute(query)
        
        subaccount_id <- db_query(sprintf(
            "SELECT id FROM cex_subaccounts 
             WHERE manager_wallet = '%s' AND subaccount_name = '%s'",
            tolower(manager), subaccount_name
        ))$id[1]
        
        return(list(
            status = "success", 
            status_code = 200, 
            message = "CEX subaccount registered successfully", 
            subaccount_id = subaccount_id,
            gas_balance_usd = total_gas_usd,
            payment_network = payment_network
        ))
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("POST", "/registerCEXSubaccount", registerCEXSubaccountHandler, serializer = serializer_json())

# Set CEX Side
setCEXSideHandler <- function(gas_wallet_api_key, subaccount_name, pair, side, max_usd, share, strategy = NULL) {
    tryCatch({
        encrypted_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        subaccount <- db_query(sprintf(
            "SELECT id, exchange, is_active FROM cex_subaccounts 
             WHERE encrypted_gas_wallet_api_key = '%s' AND subaccount_name = '%s'",
            encrypted_key, subaccount_name
        ))
        
        if (nrow(subaccount) == 0) {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
        if (!subaccount$is_active[1]) {
            return(list(status = "fail", status_code = 400, message = "Subaccount is not active"))
        }
        
        subaccount_id <- subaccount$id[1]
        
        if (is.null(strategy) || strategy == "") { strategy <- "custom" }
        
        strategy_id <- NULL
        if (tolower(strategy) != "custom") {
            strategy_result <- db_query(sprintf(
                "SELECT id FROM cex_strategies WHERE strategy_name = '%s' AND is_active = TRUE", tolower(strategy)
            ))
            if (nrow(strategy_result) > 0) { strategy_id <- strategy_result$id[1] }
        }
        
        existing <- db_query(sprintf(
            "SELECT id, side, previous_side FROM cex_bots WHERE subaccount_id = %d AND pair = '%s'",
            subaccount_id, pair
        ))
        
        if (nrow(existing) > 0) {
            bot_id <- existing$id[1]
            previous_side <- existing$side[1]
            side_changed <- previous_side != side
            
            db_execute(sprintf(
                "UPDATE cex_bots SET side = '%s', previous_side = '%s', max_usd = %.2f, share = %.2f, 
                 strategy_id = %s, last_side_change = %s, updated_at = NOW() WHERE id = %d",
                side, previous_side, as.numeric(max_usd), as.numeric(share),
                ifelse(is.null(strategy_id), "NULL", strategy_id),
                ifelse(side_changed, "NOW()", "last_side_change"), bot_id
            ))
            
            message <- if (side_changed) sprintf("Side changed: %s → %s", previous_side, side) else "Bot updated"
            return(list(status = "success", status_code = 200, message = message, bot_id = bot_id, 
                       side = side, previous_side = previous_side, side_changed = side_changed))
        } else {
            db_execute(sprintf(
                "INSERT INTO cex_bots (subaccount_id, strategy_id, pair, side, previous_side, max_usd, share, is_active)
                 VALUES (%d, %s, '%s', '%s', NULL, %.2f, %.2f, TRUE)",
                subaccount_id, ifelse(is.null(strategy_id), "NULL", strategy_id),
                pair, side, as.numeric(max_usd), as.numeric(share)
            ))
            
            bot_id <- db_query(sprintf(
                "SELECT id FROM cex_bots WHERE subaccount_id = %d AND pair = '%s'", subaccount_id, pair
            ))$id[1]
            
            return(list(status = "success", status_code = 200, message = "Bot created", bot_id = bot_id,
                       side = side, previous_side = NULL, side_changed = TRUE))
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("POST", "/setCEXSide", setCEXSideHandler, serializer = serializer_json())

# Get CEX Side
getCEXSideHandler <- function(gas_wallet_api_key, subaccount_name, pair = NULL) {
    tryCatch({
        encrypted_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        subaccount <- db_query(sprintf(
            "SELECT id, exchange, subaccount_name FROM cex_subaccounts 
             WHERE encrypted_gas_wallet_api_key = '%s' AND subaccount_name = '%s'",
            encrypted_key, subaccount_name
        ))
        
        if (nrow(subaccount) == 0) {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
        
        subaccount_id <- subaccount$id[1]
        
        # If pair is provided, get specific bot
        if (!is.null(pair) && pair != "") {
            bot <- db_query(sprintf(
                "SELECT b.id, b.pair, b.side, b.previous_side, b.max_usd, b.share, 
                        b.is_active, b.last_side_change, b.created_at, b.updated_at,
                        s.strategy_name
                 FROM cex_bots b
                 LEFT JOIN cex_strategies s ON b.strategy_id = s.id
                 WHERE b.subaccount_id = %d AND b.pair = '%s'",
                subaccount_id, pair
            ))
            
            if (nrow(bot) == 0) {
                return(list(status = "fail", status_code = 404, message = "Bot not found for this pair"))
            }
            
            return(list(
                status = "success",
                status_code = 200,
                message = "Bot details retrieved",
                bot = list(
                    id = bot$id[1],
                    subaccount_name = subaccount$subaccount_name[1],
                    exchange = subaccount$exchange[1],
                    pair = bot$pair[1],
                    side = bot$side[1],
                    previous_side = if(is.na(bot$previous_side[1])) NULL else bot$previous_side[1],
                    max_usd = as.numeric(bot$max_usd[1]),
                    share = as.numeric(bot$share[1]),
                    strategy = if(is.na(bot$strategy_name[1])) "custom" else bot$strategy_name[1],
                    is_active = bot$is_active[1],
                    last_side_change = as.character(bot$last_side_change[1]),
                    created_at = as.character(bot$created_at[1]),
                    updated_at = as.character(bot$updated_at[1])
                )
            ))
        } else {
            # Get all bots for this subaccount
            bots <- db_query(sprintf(
                "SELECT b.id, b.pair, b.side, b.previous_side, b.max_usd, b.share, 
                        b.is_active, b.last_side_change, b.created_at, b.updated_at,
                        s.strategy_name
                 FROM cex_bots b
                 LEFT JOIN cex_strategies s ON b.strategy_id = s.id
                 WHERE b.subaccount_id = %d
                 ORDER BY b.created_at DESC",
                subaccount_id
            ))
            
            if (nrow(bots) == 0) {
                return(list(
                    status = "success",
                    status_code = 200,
                    message = "No bots found for this subaccount",
                    bots = list()
                ))
            }
            
            bot_list <- list()
            for (i in 1:nrow(bots)) {
                bot <- bots[i,]
                bot_list[[i]] <- list(
                    id = bot$id,
                    pair = bot$pair,
                    side = bot$side,
                    previous_side = if(is.na(bot$previous_side)) NULL else bot$previous_side,
                    max_usd = as.numeric(bot$max_usd),
                    share = as.numeric(bot$share),
                    strategy = if(is.na(bot$strategy_name)) "custom" else bot$strategy_name,
                    is_active = bot$is_active,
                    last_side_change = as.character(bot$last_side_change),
                    created_at = as.character(bot$created_at),
                    updated_at = as.character(bot$updated_at)
                )
            }
            
            return(list(
                status = "success",
                status_code = 200,
                message = sprintf("Found %d bot(s)", nrow(bots)),
                subaccount_name = subaccount$subaccount_name[1],
                exchange = subaccount$exchange[1],
                bots = bot_list
            ))
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("GET", "/getCEXSide", getCEXSideHandler, serializer = serializer_json())

# Set CEX Strategy
setCEXStrategyHandler <- function(gas_wallet_api_key, subaccount_name, pair, strategy) {
    tryCatch({
        encrypted_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        subaccount <- db_query(sprintf(
            "SELECT id FROM cex_subaccounts WHERE encrypted_gas_wallet_api_key = '%s' AND subaccount_name = '%s'",
            encrypted_key, subaccount_name
        ))
        if (nrow(subaccount) == 0) {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
        
        bot <- db_query(sprintf(
            "SELECT id FROM cex_bots WHERE subaccount_id = %d AND pair = '%s'", subaccount$id[1], pair
        ))
        if (nrow(bot) == 0) {
            return(list(status = "fail", status_code = 404, message = "Bot not found. Create bot first using /setCEXSide"))
        }
        
        strategy_id <- NULL
        if (tolower(strategy) != "custom") {
            strategy_result <- db_query(sprintf(
                "SELECT id FROM cex_strategies WHERE strategy_name = '%s' AND is_active = TRUE", tolower(strategy)
            ))
            if (nrow(strategy_result) == 0) {
                return(list(status = "fail", status_code = 404, message = sprintf("Strategy '%s' not found", strategy)))
            }
            strategy_id <- strategy_result$id[1]
        }
        
        db_execute(sprintf(
            "UPDATE cex_bots SET strategy_id = %s, updated_at = NOW() WHERE id = %d",
            ifelse(is.null(strategy_id), "NULL", strategy_id), bot$id[1]
        ))
        
        return(list(status = "success", status_code = 200, message = sprintf("Strategy updated to '%s'", strategy),
                   bot_id = bot$id[1], strategy = strategy))
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("POST", "/setCEXStrategy", setCEXStrategyHandler, serializer = serializer_json())

# Delete CEX Bot
deleteCEXBotHandler <- function(gas_wallet_api_key, subaccount_name, pair) {
    tryCatch({
        encrypted_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        subaccount <- db_query(sprintf(
            "SELECT id FROM cex_subaccounts WHERE encrypted_gas_wallet_api_key = '%s' AND subaccount_name = '%s'",
            encrypted_key, subaccount_name
        ))
        if (nrow(subaccount) == 0) {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
        
        result <- db_execute(sprintf(
            "DELETE FROM cex_bots WHERE subaccount_id = %d AND pair = '%s'", subaccount$id[1], pair
        ))
        
        if (result > 0) {
            return(list(status = "success", status_code = 200, message = "Bot deleted successfully"))
        } else {
            return(list(status = "fail", status_code = 404, message = "Bot not found"))
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("DELETE", "/deleteCEXBot", deleteCEXBotHandler, serializer = serializer_json())

# Deactivate CEX Bot
deactivateCEXBotHandler <- function(gas_wallet_api_key, subaccount_name, pair) {
    tryCatch({
        encrypted_key <- encrypt_gas_wallet_api_key(gas_wallet_api_key)
        subaccount <- db_query(sprintf(
            "SELECT id FROM cex_subaccounts WHERE encrypted_gas_wallet_api_key = '%s' AND subaccount_name = '%s'",
            encrypted_key, subaccount_name
        ))
        if (nrow(subaccount) == 0) {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
        
        result <- db_execute(sprintf(
            "UPDATE cex_bots SET is_active = FALSE, updated_at = NOW() 
             WHERE subaccount_id = %d AND pair = '%s'", subaccount$id[1], pair
        ))
        
        if (result > 0) {
            return(list(status = "success", status_code = 200, message = "Bot deactivated successfully"))
        } else {
            return(list(status = "fail", status_code = 404, message = "Bot not found"))
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("POST", "/deactivateCEXBot", deactivateCEXBotHandler, serializer = serializer_json())

# Delete CEX Subaccount (CASCADE deletes all bots and trades)
deleteCEXSubaccountHandler <- function(manager, subaccount_name, signature = NULL) {
    tryCatch({
        # Verify signature
        if (!is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager)) {
            return(list(status = "fail", status_code = 401, message = "Invalid Signature"))
        }
        
        result <- db_execute(sprintf(
            "DELETE FROM cex_subaccounts WHERE manager_wallet = '%s' AND subaccount_name = '%s'",
            tolower(manager), subaccount_name
        ))
        
        if (result > 0) {
            return(list(status = "success", status_code = 200, message = "Subaccount deleted successfully (all bots removed)"))
        } else {
            return(list(status = "fail", status_code = 404, message = "Subaccount not found"))
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("DELETE", "/deleteCEXSubaccount", deleteCEXSubaccountHandler, serializer = serializer_json())

# Get All CEX Subaccounts for Manager
getAllCEXSubaccountsHandler <- function(manager, signature = NULL) {
    tryCatch({
        # Verify signature
        if (!is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager)) {
            return(list(status = "fail", status_code = 401, message = "Invalid Signature"))
        }
        
        # Get all subaccounts for this manager
        subaccounts <- db_query(sprintf(
            "SELECT id, subaccount_name, exchange, gas_wallet, is_active, 
                    total_balance_usd, gas_balance_usd, last_gas_check, 
                    created_at, updated_at
             FROM cex_subaccounts 
             WHERE manager_wallet = '%s'
             ORDER BY created_at DESC",
            tolower(manager)
        ))
        
        if (nrow(subaccounts) == 0) {
            return(list(status = "success", status_code = 200, message = "No subaccounts found", subaccounts = list()))
        }
        
        # Get bot counts for each subaccount
        result_list <- list()
        for (i in 1:nrow(subaccounts)) {
            sub <- subaccounts[i,]
            bots <- db_query(sprintf(
                "SELECT COUNT(*) as total_bots, 
                        SUM(CASE WHEN b.is_active = TRUE THEN 1 ELSE 0 END) as active_bots
                 FROM cex_bots b
                 JOIN cex_subaccounts s ON b.subaccount_id = s.id
                 WHERE s.manager_wallet = '%s' AND s.subaccount_name = '%s'",
                tolower(manager), sub$subaccount_name
            ))
            
            # Get asset details from CEX (includes calculated total_usd)
            balance_data <- get_cex_balance_details(sub$id)
            
            result_list[[i]] <- list(
                subaccount_name = sub$subaccount_name,
                exchange = sub$exchange,
                gas_wallet = sub$gas_wallet,
                is_active = sub$is_active,
                total_balance_usd = balance_data$total_usd,  # Use freshly calculated value
                gas_balance_usd = as.numeric(sub$gas_balance_usd),
                last_gas_check = as.character(sub$last_gas_check),
                total_bots = if(nrow(bots) > 0) bots$total_bots[1] else 0,
                active_bots = if(nrow(bots) > 0) bots$active_bots[1] else 0,
                assets = balance_data$assets,
                created_at = as.character(sub$created_at),
                updated_at = as.character(sub$updated_at)
            )
        }
        
        return(list(
            status = "success", 
            status_code = 200, 
            message = sprintf("Found %d subaccount(s)", nrow(subaccounts)),
            subaccounts = result_list
        ))
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}
pr$handle("GET", "/getAllCEXSubaccounts", getAllCEXSubaccountsHandler, serializer = serializer_json())


pr$run(host="0.0.0.0",port=8002)


