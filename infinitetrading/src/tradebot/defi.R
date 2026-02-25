######################
###		   ###
### DeFi SDK       ###
### Dr. Clare      ###
### Copyright 2025 ###
###		   ###
######################

wd = "~/infinitetrading/src/"
if (!exists("DEFI_SKIP_SOURCES") || !DEFI_SKIP_SOURCES) {
source(paste0(wd,"db.R")); source(paste0(wd,"slack.R")); source(paste0(wd,"telegram.R"))
}
load_dot_env("~/infinitetrading/src/api/.env")

coins_data <- read.csv("/home/ubuntu/infinitetrading/coins.csv",colClasses = c("character", "character", "character"))
cat("coins_data loaded:", nrow(coins_data), "rows\n")
ALCHEMY_BALANCES_KEY = Sys.getenv("ALCHEMY_BALANCES_APIKEY")
#print(ALCHEMY_KEY)

require(jsonlite); require(httr)

dhedge_ep="http://localhost:8000/"; defund_ep ="http://localhost:3000/"

#https://us-central1-dhedge-trading.cloudfunctions.net/approve?apiKey=[YOUR_API_KEY]&asset=[ASSET_CONTRACT]&platform=[EXCHNAGE_VENUE]
#https://us-central1-dhedge-trading.cloudfunctions.net/trade?apiKey=[YOUR_API_KEY]&from=[ASSET_CONTRACT_1]&to=[ASSET_CONTRACT_2]&share=[PERCENT_1]&slippage=[PERCENT_2]&platform=[EXCHNAGE_VENUE]
#api key RzdpGs9RnDMxf6ReWspa6bZF5t8ecKLy
#trader account: 0xFC7E3e0DEf830f394fF7D903DC350b1dFE0C859a

## add api key here and cloudfunctions endpoint; generate an API key
dhedge_ep2="https://us-central1-dhedge-trading.cloudfunctions.net/trade?apiKey=RzdpGs9RnDMxf6ReWspa6bZF5t8ecKLy"

coins <- function(coin, network, discord = TRUE) {
  # Make comparison case-insensitive by using tolower()
  contract <- coins_data$contract[ tolower(coins_data$symbol) == tolower(coin) & tolower(coins_data$network )== tolower(network) ]
  print(as.character(contract))
  if (length(contract) == 0) {
    errmsg <- paste0("Contract not found for ", coin, " / network: ", network)
    if (discord) {
      discord(msg = errmsg, channel = "#error-logs")
      return(0)
    } else {
      return(errmsg)
    }
  } else {
    return(contract)
  }
}

#print(coins("wstETH","optimism"))
#print(coins("WSTETH","optimism"))
get_symbol <- function(contract, network) {
  symbol <- coins_data$symbol[tolower(coins_data$contract) == tolower(contract) & coins_data$network == network]
  if (length(symbol) == 0) {
    #discord(msg=paste0("Symbol not found for contract: ", contract," / network: ",network),channel="#error-logs")
    return("Unknown")
  } else { return(symbol) }
}

decimals = function(symbol) { 
	if (symbol == "WBTC") { d = 8 }
	else if (symbol == "USDC" || symbol == "USDCN" || symbol == "USDT" || symbol == "DAI") { d = 6 }
	else { d = 18 }
	return(d)
}

#is_toros = function(coin) { 
#  if (coin == "USDpy" || coin == "ETHBULL3X" || coin == "ETHy" || coin == "MATICBULL2X" || coin == "USDmny" || coin == "BTCBULL3X" || coin == "ETHBEAR1X" || coin == "MATICBEAR1X" || coin == "BTCBEAR1X" || coin == "MATICBEAR1X" || coin == "ETHBEAR2X" || coin =="BTCBEAR2X") { return(TRUE) }
#  return(FALSE)
#}

approve_assets=function(pool,assets,env="dev",network="polygon",toros=FALSE,platform=NULL,manager="infinitetrading") {
  require(httr);require(jsonlite)
  n = length(assets)
  if (length(toros) != n) { toros = rep(toros[1],n) }
  for (i in 1:n) {
    ep = paste0(dhedge_ep,"approve?&pool=",pool)
    ep = paste0(ep,"&manager=",manager)
    if (toros[i]) { ep = paste0(ep,"&platform=toros") }
    if (!is.null(platform)) { ep = paste0(ep,"&platform=",platform) }
    ep = paste0(ep,"&network=",network)
    res = POST(url=ep,body=list(asset=coins(assets[i],network=network)),encode="json")
    Sys.sleep(5)
    res = fromJSON(content(res,as="text"))
    print(res)
  }
}

#approve_assets(pool="0xa50f3446445a1e09546d003b30c798377e97c7e4",assets="ETHBULL3X",network="arbitrum",platform="toros",manager="infinitetrading")

approvals = function() {
	pools = c(
		"0xb990f805c16b65eb9400a390fd9087e4a249e681", #1
          	"0xe8f78aaa6ac51db0ea5fe64340cbe724c2fa0079", #6
          	"0x34358e00aacaf1071c832266859b64b085a1c1ae", #20
          	"0x0693ef3a503c3653538963cc0a58e897a3cb0501"  #24
		)
	networks = rep("polygon",4)
	platforms = c('uniswapV3','toros','uniswapV3','uniswapV3')
	assets=c("LINK","ETHBULL3X","WBTC","WETH")
	n = length(pools)
	for (i in 1:n) { 
		discord(paste0(msg="Approving assets: USDC and ",asset[i], " for pool: ",pools[i]," / network: ",networks[i], " / platform: ",platforms[i]),channel="#pools-trading")
		approve_assets(pool=pools[i],assets=c(assets[i],"USDC"),network=networks[i],platform=platforms[i])
	}
}

pool_comp <- function(pool, network, protocol = "dhedge", db = FALSE,apiKey=NULL,provider="alchemy",providerKey=ALCHEMY_BALANCES_KEY) {
  # force scalars + normalize
  pool     <- tolower(as.character(pool))[1L]
  network  <- tolower(as.character(network))[1L]
  protocol <- tolower(as.character(protocol))[1L]

  # validate protocol; pick a policy: error or first value
  protocol <- match.arg(protocol, c("dhedge", "defund"))

  if (isTRUE(db)) {
    return(get_composition(pool))
  }

  comp <- switch(protocol,
    dhedge = dhedge_pool_comp(pool, network,apiKey,provider,providerKey),
    defund = defund_pool_comp(pool, network)
  )

  if (!is.null(comp)) comp else NULL
}

#######################################################################
### dhedge_pool_comp(pool,network) 				    ###
### Retrives the pool composition of any dHedge pool in any network ###
#######################################################################

dhedge_pool_comp <- function(pool,network="polygon",apiKey=NULL,provider="alchemy",providerKey=ALCHEMY_BALANCES_KEY) {
  #gql_ok <- FALSE
  #gql_out <- NULL
  #gql_err <- NULL

  #gql_out <- tryCatch({
  #  dhedge_pool_comp_gql(pool, network)
  #}, error = function(e) {
  #  gql_err <<- e
  #  NULL
  #})

  #if (!is.null(gql_out) && length(gql_out) > 0) {
  #  # sanity check: 6 columns expected
  #  if (!is.null(ncol(gql_out)) && ncol(gql_out) == 6) {
  #    return(gql_out)
  #  }
  #}
  
  require(stringr); require(httr); require(jsonlite)
  url <- paste0(dhedge_ep,"poolComposition?network=",network,"&pool=",pool)
  if (!is.null(apiKey)) url = paste0(url,"&apiKey=",apiKey)
  if (!is.null(provider)) url = paste0(url,"&provider=",provider)
  if (!is.null(provider)) url = paste0(url,"&providerKey=",providerKey)
  response <- GET(url); content <- content(response, "text"); result <- fromJSON(content, flatten=TRUE)
  poolBalances = result$msg
  print(poolBalances)
  options(digits = 18)
  n_row = nrow(poolBalances); 
  n_col = ncol(poolBalances)
  if (is.null(n_col)) { n_col = 0 }
  if (n_col == 6) {
	asset = poolBalances[,1]; isDeposit = poolBalances[,2]; assetPair=rep(0,n_row); symbol = rep(0,n_row); amount = rep(0,n_row); price = rep(0,n_row)  
    	for (i in 1:n_row) {
      		balances = as.numeric(poolBalances[i,4]); contract = tolower(poolBalances[i,1]); symbol[i] = get_symbol(contract,network)[1]
      		d = decimals(symbol=symbol[i])  
      		assetPair[i] = paste(symbol[i],"USD",sep="-")
      		amount[i] = as.numeric(poolBalances[i,4]) / (10 ^ d); price[i] = as.numeric(poolBalances[i,6])/(10^18)
    	}
    	poolBalances = cbind(asset,isDeposit,assetPair,symbol,amount,price)
    	colnames(poolBalances) = c('asset', 'isDeposit', 'assetPair', 'symbol', 'amount','price')
    	print(poolBalances)
  }
  else { 
	  discord(msg=paste0("Error fetching pool balance for: ",pool,"/ network: ",network),channel="#error-logs")
	  #poolBalances = pool_comp(pool,network,protocol="dhedge",db=TRUE)
  	  poolBalances = c()
  }
  return(poolBalances)
}
dhedge_pool_comp_gql <- function(pool, network = "polygon",
                                 endpoint = "https://api-v2.dhedge.org/graphql") {
  require(httr); require(jsonlite); require(stringr)

  # GraphQL payload (keep order as returned by API)
  gql <- '
  query ($address: String!) {
    fund(address: $address) {
      fundComposition {
        tokenAddress
        isDeposit
        amount
        rate
      }
    }
  }'

  # Call GraphQL
  resp <- POST(
    endpoint,
    body = list(query = gql, variables = list(address = tolower(pool))),
    encode = "json"
  )

  if (http_error(resp)) {
    try(discord(msg = paste0("GraphQL error fetching pool balance for: ", pool,
                             " / network: ", network, " (HTTP ",
                             status_code(resp), ")"),
                channel = "#error-logs"), silent = TRUE)
    return(c())
  }

  content_txt <- content(resp, "text", encoding = "UTF-8")
  parsed <- fromJSON(content_txt, flatten = TRUE)

  # Basic validation
  if (is.null(parsed$data$fund$fundComposition)) {
    try(discord(msg = paste0("Empty fundComposition for: ", pool,
                             " / network: ", network),
                channel = "#error-logs"), silent = TRUE)
    return(c())
  }

  # Keep original print & digits behavior
  options(digits = 18)

  fc <- parsed$data$fund$fundComposition
  # Ensure data.frame (preserve order as returned)
  poolBalances <- as.data.frame(fc, stringsAsFactors = FALSE)

  # Build output to mirror original structure:
  # asset, isDeposit, assetPair, symbol, amount, price
  n_row <- nrow(poolBalances)
  asset     <- rep(NA_character_, n_row)
  isDeposit <- rep(FALSE, n_row)
  assetPair <- rep(NA_character_, n_row)
  symbol    <- rep(NA_character_, n_row)
  amount    <- rep(NA_real_, n_row)
  price     <- rep(NA_real_, n_row)

  for (i in seq_len(n_row)) {
    contract        <- tolower(poolBalances$tokenAddress[i])
    asset[i]        <- contract
    isDeposit[i]    <- isTRUE(poolBalances$isDeposit[i])
    # Your existing helpers:
    symbol[i]       <- get_symbol(contract, network)[1]
    d               <- decimals(symbol = symbol[i])
    assetPair[i]    <- paste(symbol[i], "USD", sep = "-")
    # GraphQL returns raw units in `amount` and a 1e18-scaled rate in `rate`
    amount[i]       <- as.numeric(poolBalances$amount[i]) / (10 ^ d)
    price[i]        <- as.numeric(poolBalances$rate[i]) / (10 ^ 18)
  }

  # Match original: cbind -> matrix (usually coerces to character)
  out <- cbind(asset, isDeposit, assetPair, symbol, amount, price)
  colnames(out) <- c("asset", "isDeposit", "assetPair", "symbol", "amount", "price")

  # Optional debug print like original
  print(out)

  return(out)
}
#dhedge_pool_comp_gql(pool="0xb990f805c16b65eb9400a390fd9087e4a249e681",network="polygon")

#pool_comp(pool="0xb990f805c16b65eb9400a390fd9087e4a249e681",network="polygon",db=TRUE)                
#comp = pool_comp(pool="0xe8f78aaa6ac51db0ea5fe64340cbe724c2fa0079",network="polygon",db=FALSE)
#print(comp)

defund_pool_comp=function(pool,network="polygon") { 
	require(httr); require(jsonlite)
	url = paste0(defund_ep,"poolComposition?pool=",pool,"&network=",network)
	res = GET(url=url)
  	res = fromJSON(content(res,as="text"))
	poolBalances = res$msg$tokenBalances
	#poolBalances = poolBalances[poolBalances[,2] >0,]
  	options(digits = 18)
	#print(poolBalances)
  	n = nrow(poolBalances); asset = poolBalances[,1]; isDeposit = rep(TRUE,n); assetPair=rep(0,n); symbol = rep(0,n); amount = rep(0,n)
  	if (ncol(poolBalances) == 4) {
                for (i in 1:n) {
                        balances = as.numeric(poolBalances[i,2])
                        contract = tolower(poolBalances[i,1])
                        #print(paste0("contract: ", contract))
                        #print(paste0("is contract usdc?", contract==coins("USDC",network=network)))
                        #print(paste0("balances: ", balances))
                        if (contract == tolower(coins("WETH",network=network))) {
                                symbol[i] = "WETH"
                                amount[i] = balances/(10^18)
                         }
                        else if (contract == tolower(coins("WBTC",network=network))) {
                                symbol[i] = "WBTC"
                                amount[i] = balances/(10^8)
                         }
                         else if (contract == tolower(coins("WMATIC",network=network))) {
                                symbol[i] = "WMATIC"
                                amount[i] = balances/(10^18)
                         }
                         else if (contract == tolower(coins("USDC",network=network))) {
                                symbol[i] = "USDC"
                                amount[i] = balances/(10^6)
                         }
                         assetPair[i] = paste(symbol[i],"USD",sep="-")
                         #else if (contract == coins("USDT",network=network)) {
                         #       assetPair[i] = "USD-USD"
                         #       symbol[i] = "USDT"
                         #       amount[i] = balances/(10^6)
                         #}
                }
        }
        poolBalances = cbind(asset,isDeposit,assetPair,symbol,as.numeric(amount))
        colnames(poolBalances) = c('asset', 'isDeposit', 'assetPair', 'symbol', 'amount')
        return(poolBalances)
}

options(scipen=18)

uniswap_pool_fees = function(coin1,coin2,network) {
        fee = 500
        if (coin1 == "USDC" || coin2 == "USDC") { usdc = TRUE }
        else { usdc = FALSE }
        if (network == "optimism") {
                if (usdc && (coin1 == "SNX" || coin2 == "SNX")) { fee = 3000 }
                else if (usdc && (coin1 == "OP" || coin2 == "OP")) { fee = 3000 }
        	else if (usdc && (coin1 == "USDCN" || coin2 == "USDCN")) { fee = 1000 }
	}
        if (network == "polygon") {
		if (usdc && (coin1 == "USDCN" || coin2 == "USDCN")) { fee = 1000 }
                if (usdc && (coin1 == "stMATIC" || coin2 == "stMATIC")) { fee = 3000 }
		else if (usdc && (coin1 == "SOL"|| coin2=="SOL")) { fee=10000 }
		else if (coin1 == "WMATIC" && coin2 == "stMATIC")  { fee = 3000 } 
		else if (usdc && (coin1 == "LINK" || coin2 == "LINK")) { fee = 3000 }
        	else if (usdc & (coin1 == "SNX" || coin2 == "SNX")) { fee = 3000 }
		else if (usdc & (coin1 == "GNS" || coin2 == "GNS")) { fee = 3000 }
		else if (usdc & (coin1 == "LDO" || coin2 == "LDO")) { fee = 3000 } 
	}
        return(fee)
}

max_usd= function(asset) {
	asset = toupper(asset)
        if (asset=="WBTC" || asset == "WETH" || asset == "WMATIC") { max_usd = 5000 }
        else { max_usd = 1000 }
}

is_enabled = function(asset,composition=NULL)  {
	asset_row = c();
	if (!is.null(composition)) asset_row = which(composition[,4] == asset);
	return(ifelse(length(asset_row) > 0,TRUE,FALSE))
}

get_balance_bot = function(asset,composition=NULL,bignumber=FALSE)  {
        asset_row = c(); asset_balance = 0
        if (!is.null(composition)) { asset_row = which(composition[,4] == asset); }
        if (length(asset_row) > 0) { 
		if (!bignumber) asset_balance = as.numeric(composition[asset_row,5])
        	else asset_balance = as.numeric(composition[asset_row,6]); 
        }
        return(asset_balance)
}

#get_balance("WETH",composition=composition_db)

###############################
#                             #
# get_usd_price()             #
# Gets the usd price of an    #
# asset given the composition #
#                             #
###############################

get_usd_price = function(asset,composition) {
        asset_row = c(); asset_price = 0
        if (!is.null(composition)) { asset_row = which(composition[,4] == asset); }
        if (length(asset_row) > 0) { asset_price = as.numeric(composition[asset_row,6]); }
        asset_price = as.numeric(asset_price)
	if (asset_price > 0) { return(asset_price) }
	else { asset_price = 0 }
	return(asset_price)
}

get_usd_value= function(asset,composition) { return(get_usd_price(asset,composition)*get_balance_bot(asset,composition)) }

#comp = pool_comp(pool="0xe4824fb9b7af29ecc0efa5c88e28262ac55822ba",network="optimism")
#usd_value = get_usd_value(asset="ETHBEAR1X",composition=comp)
#print("eth usd value")
#from="ETHBEAR1X"
#print(usd_value)
#print("get balance from ETHBEAR1X using compositon")
#print(get_balance("ETHBEAR1X",comp))

get_allocation = function(asset,pool=NULL,assets,prices,composition=NULL,network="polygon",protocol="dhedge") {
  if (is.null(composition)) { composition = pool_comp(pool,network=network,protocol=protocol) }
  if (is.null(ncol(composition))) { discord(paste0("Error: failed to load the pool composition for rebalancing this pool: ", pool, " / network: ",network)) }
  n = length(assets); balances =rep(0,n); price = 0; balance = 0;
  for (i in 1:n) {
          balances[i] = get_balance_bot(composition,asset=assets[i])
          if (asset==assets[i]) { balance = balances[i]; price = prices[i] }
  }
  total_value <- sum(balances * prices)
  return( (balance * price) / total_value)
}

share_from_asset = function(asset,composition,max_usd) { 
	#resolver la ecuacion de cuanto es el share del pool para que te de solve(max_usd(asset))
	coin_usd_value = get_usd_value(asset=asset,composition=composition)
	if (coin_usd_value <= max_usd) { share=100 }
	else { share = round(max_usd/coin_usd_value,2) }
	return(share)
}

get_contract_from_symbol <- function(symbol,comp) {
  if (is.null(comp) || is.null(symbol)) return(NULL)

  cn <- tolower(colnames(comp))
  i_sym   <- if (!is.null(cn)) match("symbol", cn) else 4
  i_asset <- if (!is.null(cn)) match("asset",  cn) else 1

  s <- tolower(as.character(if (is.data.frame(comp)) comp[[i_sym]] else comp[, i_sym, drop = TRUE]))
  a <- as.character(if (is.data.frame(comp)) comp[[i_asset]] else comp[, i_asset, drop = TRUE])

  j <- which(s == tolower(symbol))[1]
  if (is.na(j)) return(NULL)
  a[j]
}

get_decimals = function(asset) {
        asset = toupper(asset)	
	if (asset == "WBTC") { decimals = 8 }
	else if (asset == "USDC" || asset == "USDT" || asset == "USDCN") { decimals = 6 }
	else { decimals = 18 }
	return(decimals)
}

is_btc_bull = function(asset) return((asset %in% c("BTCBULL3X","BTCBULL2X","BTCBULL4X")))
is_eth_bull = function(asset) return((asset %in% c("ETHBULL3X","ETHBULL2X")))
is_bull = function(asset) return((is_btc_bull(asset) || is_eth_bull(asset)))
is_bear = function(asset) return((asset %in% c("ETHBEAR1X","BTCBEAR1X")))
is_toros = function(asset) return((is_bull(asset) || is_bear(asset)))

is_eth = function(symbol) {
        symbol = toupper(symbol)
        return (is_eth_bull(symbol) || symbol == "WETH" || symbol == "FRXETH" || symbol == "ALETH" || symbol == "RETH" || symbol == "WSTETH" || symbol == "WEETH")
} 

is_btc = function(symbol) {
        symbol = toupper(symbol)
        return (is_btc_bull(symbol) || symbol == "WBTC" || symbol == "TBTC")
} 

short_networks = c("arbitrum","optimism")

options(error=recover)
trade = function(ep = "local",from,to,platform="odos",network,share=100,slippage=1,pool,amount=NULL,protocol="dhedge",composition = NULL,max_usd=NULL,manager=NULL,apiKey=NULL) {
	response = tryCatch({ 
		if (protocol == "dhedge") trade_ep = dhedge_ep
		else if (protocol == "defund") trade_ep = defund_ep
		#composition=pool_comp(pool,network=network,protocol=protocol)
		#print(composition)
		if (!is.null(composition)) {
		       	if (get_balance_bot(from,composition) == 0) return(paste0("The 'from' asset ", from," balance is 0 on: ",pool))
			if (!is_enabled(to,composition)) return(paste0("The destination asset ",to," is not enabled inside this pool: ",pool))
		}
		trade_ep = paste0(trade_ep,"trade?from=") 
		
		if (from == "ETHBEAR1X") { to = "USDC"; platform = "toros" }
		else if (from == "BTCBEAR1X") { to = "USDC"; platform="toros" }
		
		if (is_bear(to)) { from = "USDC" } 
		if (is_btc_bull(from) && to == "USDC") { to = "WBTC"; platform = "toros" }
		if (is_eth_bull(from) && to == "USDC") { to = "WETH"; platform = "toros" }
		if (is_toros(to)) { platform ="toros" }
		
		to_c = coins(to,network=network); from_c = coins(from,network=network);
		if (!is.null(max_usd) && !is.null(composition)) { share = min(share_from_asset(from,composition,max_usd),share) }
		
		ep = paste0(trade_ep,from_c,"&to=",to_c,"&slippage=",slippage,"&pool=",pool,"&network=",network,"&platform=",platform)
                if (is_toros(from)) ep = paste0(ep,"&withdrawal=true")

		if (!is.null(amount)) { 
			decimals = get_decimals(from)
                        amount = floor(amount*10^(decimals))
		}
		else { amount = 0 } 
		if (amount > 0) { ep = paste0(ep,from_c,"&amount=",amount) }
		else { ep = paste0(ep,"&share=",share) }
		
		#print(typeof(ep))
		if (protocol == "dhedge") {
			if (platform == "uniswapV3") ep = paste0(ep,"&feeAmount=",uniswap_pool_fees(coin1=from,coin2=to,network=network))	
			pool_url =  paste0("https://app.dhedge.org/pool/",pool)
		}
		
		#Deprecated DeFund
		#else if (protocol == "defund") {
		#	if (network == "polygon") chainid = 137 
		#	pool_url = paste0("https://defund.io/v1.5.0/app/funds/",chainid,"/",pool)
		#}

		msg = paste0("Sending trade: from: ",from," (",from_c,") to: ",to," (",to_c,") / ", network," / ",pool_url)
		
		if (!is.null(apiKey)) { ep = paste0(ep,"&apiKey=",apiKey) }
		else if (!is.null(manager)) { ep = paste0(ep,"&manager=",manager); msg = paste0(msg," / manager: ",manager) }
        	
		discord(msg=msg,channel="#pools-trading")
		print(msg)
		print(paste0("sending trade instructions to this endpoint: ",ep))
		
		#print(typeof(ep))
		res = GET(ep, timeout(120));
		
		# Print the raw response content before parsing
		raw_content = content(res, as="text")
		print(paste0("Raw response: ", raw_content))
        	res = fromJSON(content(res,as="text"))
		print(res);
		
		#discord(res$msg,channel="#pools-trading");
		print(paste0("trade(ep='local',from='", from,"',to='", to,"',platform='", platform,"',network='", network,"',share=", share,",slippage=", slippage,",pool='", pool,"',protocol='", protocol,"',max_usd=", max_usd,",apiKey='", apiKey,"')"))
        	if (!is.null(res)) {
			if (!is.null(res$msg)) { 
				if (is.list(res$msg)) { res$msg = as.character(unlist(res$msg)) }
				#if (grepl("STF", res$msg)) {
                			# Safe Transfer Failed, retry after approving
                			#print("Approval issue detected. Attempting to approve token.")
                			#token_approval(from_c, to_c, pool, network)  # Call a function to approve the token
                			# Retry the trade after approval
                			#return(trade(ep, from, to, platform, network, share, slippage, pool, amount, protocol, composition, max_usd, manager, apiKey))
            			#} else if (grepl("UNPREDICTABLE_GAS_LIMIT", res$msg)) {
                		#	msg = "Unpredictable gas limit, transaction may fail." 
				#	print(msg)
                		#	discord(msg=msg,channel="#pools-trading") 
				#	return("Gas estimation issue")
            			#}
			}
                	#lack_message(res,channel="#trade-logs");
                	if (!is.null(res$status) && !is.null(res$msg)) {
				msg = paste("status:",res$status,"tx reponse:",res$msg[1],"/",res$msg[2])
				print(msg)
                        	discord(msg=msg,channel="#pools-trading")
                        	#slackr_bot(res,incoming_webhook_url=slack_webhook("#trade-logs"))
                	}
        	}
		res
	}, error = function(e) { 
		e$message
	        # Capture detailed error information
		print(paste0("Error: ", e$message))
	        #print(paste0("Call: ", sys.calls()))
		#print(paste0("Traceback: ", traceback()))
		return(e$message)
	}
	) 
	return(response)
}

#get_tx_status <- function(tx_hash,network) {
# Replace 'YOUR_API_KEY' with your actual Etherscan API key
#  if (network == "optimism") { 
#	api_key <- "TU3ZUYJGCYMFNFWJ966WKWHSPDG5CCW5QM"
#  	base_url <- "https://api-optimistic.etherscan.io/api?module=transaction&action=gettxreceiptstatus&txhash="
#  }
#  endpoint <- paste0(base_url, tx_hash, "&apiKey=",api_key)
#  response <- GET(url = endpoint)
#  content <- content(response, as = "text")
#  parsed_content <- fromJSON(content)
#  print(parsed_content)
#}

create_wallet = function() {
    library(jsonlite)
    # Define the URL of the API endpoint
    url <- "localhost:8000/createWallet"
    # Perform the POST request
    response <- POST(url)
    # Check the status code of the response
    if (status_code(response) == 200) {
        # If the response is OK, print the contents
        response <- content(response, "text")
        parsed_response <- fromJSON(response)
        return(parsed_response)
    } else {
        # If the response is not OK, print the status code
        print(paste("Failed with status", status_code(response)))
    }
}
#res = trade(ep="local",from="wstETH",to="USDC",platform="toros",network="arbitrum",share=100,slippage=1,pool="0xa50f3446445a1e09546d003b30c798377e97c7e4",protocol="dhedge",max_usd=10000000,manager="infinitetrading");
#print(res)

#apiKey="9d882015534cbe5318f3c0f6083683175f008304ff769367b0e14d07759076cecbe8258b7fc7df152de65230950784c099197abb3e9e8a507ac0006b3da3b18c")
#res = trade(ep="local",from="USDC",to="BTCBEAR1X",platform="toros",network="polygon",share=100,slippage=1,pool="0x34358e00aacaf1071c832266859b64b085a1c1ae",protocol="dhedge",max_usd=10000000,apiKey="9d882015534cbe5318f3c0f6083683175f008304ff769367b0e14d07759076cecbe8258b7fc7df152de65230950784c099197abb3e9e8a507ac0006b3da3b18c")

#approve_assets(pool="0x37849922d4b071254e25aa036a94442b059fdb60",network="optimism",assets=c("USDCN","USDC","WBTC"),platform="uniswapV3",manager = "infinitetrading")
