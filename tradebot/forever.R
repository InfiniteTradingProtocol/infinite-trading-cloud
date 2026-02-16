
# Dynamic path detection - works in both local and EC2 environments
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    script_dir = dirname(normalizePath(ofile))
  } else {
    script_dir = normalizePath(".")
  }
  # Navigate up from tradebot/ to repo root
  wd = paste0(dirname(script_dir), "/")
}
publicSleepInterval = 0.34

# Source dependencies
# source(paste0(wd,"slack.R"))
# source(paste0(wd,"tradebot/web3.R"))
require("quantmod");require("rgdax"); require("httr"); require("coinmarketcapr"); require("slackr"); require("lubridate"); require("PerformanceAnalytics")

public_ticker_new = function (product_id = "BTC-USD")
{
	product_id <- toupper(product_id)
        req.url <- paste0("/products/", product_id, "/ticker")
	content <- parse_response_new(path = req.url)
 	content = fromJSON(content(content,as="auto"))
        content <- as.data.frame(content)
	content$time <- strptime(content$time, "%Y-%m-%dT%H:%M:%OS")
	content$price <- as.numeric(content$price)
	content$size <- as.numeric(content$size)
	content$bid <- as.numeric(content$bid)
	content$ask <- as.numeric(content$ask)
	content$volume <- as.numeric(content$volume)
	content <- as.data.frame(content)
	return(content)
}
parse_response_new = function(path, query = "NA_character") {
	api.url <- "https://api.pro.coinbase.com"; response <- httr::GET(url = url, query = query)
	if (response$status_code != 200) { stop(message) }
	return(response)
}
coin_allocations = function(coins = c("BTC","ETH","LTC","LINK","CRV","MATIC","SOL","ADA","UNI","AAVE"),weights,formula="mc",ndays=365*2) {
    	setup("9b2e32b5-5563-4ded-8ee3-609d897669db"); n = length(coins); mc = rep(0,n); prices = rep(0,n); supply = rep(0,n); sortinos = rep(0,n)
	quotes = get_crypto_quotes(symbol=coins)
	for (i in 1:n) { 
		pair = paste(coins[i],"-USD",sep="") 
	        if (formula == "mc") { ohlc = pull_data(pair,timeframe="5m",exchange="coinbase",training_size = 1) }
		else if (formula == "mc_sortino") { ohlc = pull_data(pair,timeframe="1d",exchange="coinbase",training_size=ndays) }
		#prices[i] = public_ticker_new(product_id = pair)$price
		Sys.sleep(1)
		DailyReturns = (Cl(ohlc) - Op(ohlc))/Op(ohlc)
		dates= as_datetime(ohlc[,1])
		traderyDailyReturns <- data.frame(dates,DailyReturns)
		traderyDailyReturns$dates <- as.Date(traderyDailyReturns$dates)
		traderyDailyReturns$dates <- as.POSIXct(traderyDailyReturns$dates)
		dailyreturns_coin <- xts(traderyDailyReturns$DailyReturns, order.by = traderyDailyReturns$dates)
		sortinos[i] = max(0,SortinoRatio(dailyreturns_coin))
		prices[i] = Cl(ohlc[nrow(ohlc),])
		print(prices[i])
		quote = quotes[quotes$symbol==coins[i]]
		supply[i] = quote$circulating_supply
	}
	Sys.sleep(1)
	mc = prices*supply
	if (formula == "mc") { allocations = paste(round((mc/sum(mc))*100,2),"%",sep="") }
	else if (formula == "mc_sortino") { 
		allocations = paste(round(( (mc/sum(mc))*weights[1] + (sortinos/sum(sortinos))*weights[2] )*100,2),"%",sep="") 
	}
	print(coins); print(prices); print(allocations)
	return(cbind(coins,allocations))
}
last_report_day = -1
while (1) { 
	if (day(Sys.time()) != last_report_day) { 
		alloc = coin_allocations(coins=c("BTC","ETH","MATIC","LTC","LINK","ARB","OP"))
		print(alloc)
		last_report_day = day(Sys.time())
		allocation="Marketcap Based Allocations for Richport"
		slack_message(allocation,channel="#allocations")
		slack_message(alloc,channel="#allocations")
                alloc = coin_allocations(coins=c("BTC","ETH","MATIC","LTC","LINK","ARB","OP"))
		print(alloc)
	       	slack_message(alloc,channel="#allocations")
		weights = c(0.70,0.30)
	        alloc = coin_allocations(formula="mc_sortino",weights=weights)
		print(alloc)
		allocation=paste("Marketcap + Sortino Based Allocations with weights:",weights[1],weights[2],sep=" ")
		slack_message(allocation,channel="#allocations")
		slack_message(alloc,channel="#allocations") 
		alloc = coin_allocations(coins=c("BTC","ETH","MATIC","LTC","LINK","ARB","OP"),formula="mc_sortino",weights=weights)
		print(alloc)
		allocation=paste("Marketcap + Sortino Based Allocations with weights: ",weights[1],weights[2],sep=" ")
		slack_message(allocation,channel="#allocations")
		slack_message(alloc,channel="#allocations")
	}
  	Sys.sleep(60*60)
}

