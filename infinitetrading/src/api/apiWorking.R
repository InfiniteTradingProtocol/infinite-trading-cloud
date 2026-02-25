require(plumber); require(lubridate); require(jsonlite); require(httr);

#require(memoise)

wd = "~/infinitetrading/src/"

sources = function(files) { for (i in 1:length(files)) { source(paste0(wd,files[i])) } }


sources(c("api/helpers/graphQL.R","api/getGasBalances.R","tradebot/defi.R","api/helpers/apiHelpers.R","/api/messaging.R","/api/db.R","/api/encryption.R"))

print("After load")

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

getContractHandler <- function(coin, network) { coins(coin,network,discord=FALSE) }
pr$handle("GET", "/getContract", getContractHandler, comment = "
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

approveHandler = function(network,protocol,pool,asset,platform,apiKey,short) {
        res = c()
        if (asset == "BTC") { asset = "WBTC" }
        else if (asset == "USD") { asset = "USDC" }
        else if (asset =="ETH") { asset = "WETH" }
        else if (asset == "MATIC" || asset=="POL") { asset = "WMATIC" }
        #CHECK IF THE GAS WALLET IS LINKED TO POOL
        #CHECK IF THE GAS WALLET HAS BALANCE
        if (!isValidApiKey(network,protocol,pool,apiKey)) {
                res = c(); res$status <- 401;
                return(list(status="fail",status_code=401,message="The API Key is invalid or it has not linked to the specified pool"))
        }
        url = paste0(ep,"approve?network=",network,"&apiKey=",apiKey,"&pool=",pool)
        if (isValidEthereumAddress(asset)) { 
		asset_contract = asset
		symbol = getSymbolHandler(asset,network)
	}
        else { 
	        if (asset == "BTC") { asset = "WBTC" }
        	else if (asset == "USD") { asset = "USDC" }
        	else if (asset =="ETH") { asset = "WETH" }
        	else if (asset == "MATIC" || asset=="POL") { asset = "WMATIC" }
		asset_contract = getContractHandler(asset,network)
		symbol=asset 
	}
        if (is.null(asset_contract)) { return(list(status="fail",status_code=400,message="Unsupported asset for the specified network and protocol")) }
        if (grepl("BULL", symbol, ignore.case = TRUE) || grepl("BEAR", symbol, ignore.case = TRUE)) { platform <- "toros" }
	url = paste0(url,"&platform=",platform)
	print(paste0("approving asset: ", asset, " / contract: ",asset_contract))
        response <- POST(url,body=list(asset=asset_contract),encode="json")
        print(paste0("approve url: ",url," / asset contract: ", asset_contract))
        response_content <- content(response, "text")
        parsed_response <- fromJSON(response_content)
        if (status_code(response) == 200) {
                print(parsed_response$msg)
                #cat("message: ", message, "\n")
                res$status = 200
                result <- list(status="success",status_code=200,message="Asset approved")
        } else {
                print(parsed_response$msg)
                print(paste("Failed with status", status_code(response)))
                res$status = status_code(response)
                result <- list(status="fail",status_code=400,message="Approve failed, try again or contact support")
        }
        # add here checks if the values are correct to return this, otherwise return the error.
        return(result)
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

pr$handle("POST","/getAllGasBalance", getAllGasBalanceHandler, serializer = serializer_json())

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

setSideHandler = function(apiKey,protocol,pool,network,pair,side,threshold,max_usd,slippage,share,platform) {
	if (isValidApiKey(network,protocol,pool,apiKey)) { setSide(protocol=protocol,pool=pool,network=network,pair=pair,side=side,threshold=threshold,slippage=slippage,max_usd=max_usd,share=share,platform=platform) }
    	else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}
pr$handle("POST","/setSide",setSideHandler, serializer = serializer_json())

#========================================================================================================================

getSideHandler = function(apiKey,protocol,pool,network) {
        if (isValidApiKey(network,protocol,pool,apiKey)) { getSide(protocol=protocol,pool=pool,network=network) }
        else { res = c(); res$status <- 401; list(status="fail",status_code=401,message="Invalid API key") }
}
pr$handle("POST","/getSide",getSideHandler, serializer = serializer_json())

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
pr$handle("POST","/getTotalYield",getTotalYieldHandler, serializer = serializer_json())

#========================================================================================================================

getEstimatedAnualYieldHandler = function(pool,apiKey) {
        if (apiKey=="frontend") return(getEstimatedAnualYield(pool))
        list(status="fail",status_code=401,message="Invalid API Key")
}
pr$handle("POST","/getEstimatedAnualYield",getEstimatedAnualYieldHandler, serializer = serializer_json())

#========================================================================================================================

getAllYieldsHandler = function(apiKey) {
        if (apiKey=="frontend") return(getAllYields())
        list(status="fail",status_code=401,message="Invalid API Key")
}
pr$handle("POST","/getAllYields",getAllYieldsHandler, serializer = serializer_json())


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

pr$handle("POST","/getGasWalletPools",getGasWalletPoolsHandler, serializer = serializer_json())

#========================================================================================================================

associateGasWalletHandler <- function(apiKey,manager,label,signature=NULL) {
	if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
        label = substr(label, 1, min(42, nchar(label)))
	wallet = getWallet(apiKey)
        if (!isValidAPIKey(apiKey)) return(list(status="fail",status_code=401,message="The API Key is invalid"))
        if (!isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(associateGasWallet(wallet,manager,label,apiKey))
}

pr$handle("POST","/associateGasWallet",associateGasWalletHandler,serializer = serializer_json())


#========================================================================================================================

#I need to add here the signature! 
#Remove the 'frontend' api key needed.
#Return the API Keys.

getAssociatedGasWalletsHandler <- function(apiKey,manager,signature) {
        if (apiKey != "frontend") return(list(status="fail",status_code=401,message="Invalid API Key"))
        if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }
	if (!isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(getAssociatedGasWallets(manager))
}

pr$handle("GET","/getAssociatedGasWallets",getAssociatedGasWalletsHandler,serializer = serializer_json())

#========================================================================================================================

#========================================================================================================================

deassociateGasWalletHandler <- function(apiKey,wallet, manager,signature) {
	if ( !is_signature_format_valid(signature) || !verifySignature(signature_message, signature, manager) ) { return(list(status="fail",status_code=401,message="Invalid Signature")) }    
 	if (!isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) return(list(status="fail",status_code=401,message="Invalid Wallet or Manager"))
        return(deassociateGasWallet(wallet,manager))
}

pr$handle("POST","/deassociateGasWallet",deassociateGasWalletHandler,serializer = serializer_json())

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

vaultTradeHandler <- function(network,pool,protocol,platform,apiKey,from, to, slippage, share, amount) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        
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
	ignore_share=FALSE
	if (amount == "NA") { amount = NA }
	if (!is.na(amount)) {
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
        discord(msg=msg,channel="#api-logs",db=FALSE)
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
        response <- GET(url)
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
    discord(msg = msg, channel = "#api-logs", db = FALSE)

    return(res)
}
pr$handle("POST","/repay",repayHandler, seriealizer = serializer_json())

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
        response <- GET(url)
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
    discord(msg = msg, channel = "#api-logs", db = FALSE)

    return(res)
}

pr$handle("POST", "/borrow", borrowHandler, serializer = serializer_json())

#========================================================================================================================

lendHandler <- function(apiKey, protocol, pool, network, asset, share, amount = NULL, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    url <- paste0(ep, "lend?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,
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
        response <- GET(url)
        content_response <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

        if (status_code(response) == 200) return(response)
        res <- list(status = "fail", status_code = status_code(response), message = content_response)
    }

    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " lend invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  " / share: ", share, " / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    discord(msg = msg, channel = "#api-logs", db = FALSE)
    return(res)
}
pr$handle("POST","/lend",lendHandler, seriealizer = serializer_json())

#========================================================================================================================

unlendHandler <- function(apiKey, protocol, pool, network, asset, share=NULL, amount, platform) {
    protocol <- tolower(protocol); pool <- tolower(pool); network <- tolower(network); platform <- tolower(platform)
    check <- api_check(apiKey = apiKey, protocol = protocol, pool = pool, wallet = NULL, network = network)
    if (check$status == "fail") return(check)

    res <- list(status = "success")
    url <- paste0(ep, "unlend?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,
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
        response <- GET(url)
        content_response <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")

        if (status_code(response) == 200) return(response)
        res <- list(status = "fail", status_code = status_code(response), message = content_response)
    }

    masked_api <- mask_api(apiKey)
    msg <- paste0(res$status, " lend invoked apiKey: ", masked_api,
                  " / pool: ", pool, " / protocol: ", protocol,
                  " / network: ", network, " / asset: ", asset,
                  " / share: ", share, " / amount: ", amount,
                  " / platform: ", platform, " / response: ", res$message)
    print(msg)
    discord(msg = msg, channel = "#api-logs", db = FALSE)
    return(res)
}
pr$handle("POST","/unlend",unlendHandler, seriealizer = serializer_json())

#========================================================================================================================

pr$run(host="0.0.0.0",port=8002)


