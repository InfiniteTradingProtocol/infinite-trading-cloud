###############################
#Classification CCXT Trade Bot#
# Copyright Tradery Labs 2021 #
# Author: Mr. Richard Clare   #
###############################


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
publicSleepInterval = 0.1

source(paste(wd,"basic.R",sep=""))
require(reticulate); source_python(path.expand(paste0(wd,'sendInstruction.py')))
require(quantmod); require(stringr); require(TTR); require(httr); require(rgdax); require(jsonlite); require(lubridate); require(snakecase)

TradeBot_with_stops = function(exchanges,wallets,models,pairs,buy_thresholds,sell_thresholds,candle_close=FALSE,entry=FALSE,mp=0.10,max_usd=500,tradebot="light",sides = "hold",channel="#ccxt-wallets",client=NULL,report=FALSE,stoploss="default",trades_channel="#trade-logs") { 
  n = length(pairs)
  if (length(exchanges) == 1) { exchanges = rep(exchanges,n) }
  if (length(mp) == 1) { mp = rep(mp,n) }
  if (length(entry) == 1){ entry = rep(entry,n) }
  if (length(stoploss) == 1){ stoploss = rep(stoploss,n) }
  if (length(candle_close) == 1) { candle_close = rep(candle_close,n) } 
  if (length(max_usd) == 1) { max_usd = rep(max_usd,n) }
  if (length(tradebot) == 1){ tradebot = rep(tradebot,n) }
  if (length(sides) == 1) { sides = rep(sides,n) }
  if (is.null(sides)) { sides = rep("hold",n) }
  report_matrix = matrix(nrow=n,ncol=9)
  colnames(report_matrix) = c("Wallet","Model","Side","B/S","P","Close","SL","C/USD","Alloc")
  for (i in 1:n){ 
      total_usd = 0;
      probabilities = read_probabilities('probabilities')
      stop_losses = read_stop_losses('probabilities')
      if (!any(probabilities[,1] == models[i])) { 
     	print("error: model not found")
        print(wallets[i])
	print(models[i])
	next
      }
      if (!is.null(client)) { client_info = paste("Client: ",client," / ",sep="") }
      else { client_info ="" }
      old_buy_prob = probabilities[probabilities[,1] == models[i],3]
      buy_prob = probabilities[probabilities[,1] == models[i],4]
      last_close =probabilities[probabilities[,1] == models[i],5]
      timeframe = probabilities[probabilities[,1] == models[i],2]
      close = last_close;
      old_side = sides[i]
      stop_price = 0;
      stop_price_up = Inf
      if (stoploss[i] != "default") { 
      	stop_loss = tolower(paste(pairs[i],timeframe,stoploss[i],sep="_"))
      	if (!any(stop_losses[,1] == stop_loss)) { 
		print("error: stop loss not found, using no stoploss")
		stop_price = 0; stop_price_up = Inf
	}
      	else {
	      stop_price_up = stop_losses[stop_losses[,1] == stop_loss,2] 
	      stop_price = stop_losses[stop_losses[,1] == stop_loss,3] 
      	}
      }
      if (candle_close[i]) { new_prob = buy_prob; buy_prob = old_buy_prob; }
      else { new_prob = buy_prob } 
      if (stoploss[i] == "default" || stop_price== 0) {
      	if (buy_prob >= buy_thresholds[i] && new_prob >=sell_thresholds[i]) { sides[i] = "buy"; entry[i] = TRUE; }
     	else if (buy_prob <= sell_thresholds[i] && new_prob <= buy_thresholds[i]) { sides[i] = "sell"; entry[i] = FALSE }
      	else { sides[i] = "hold"; }
      }
      else { 
	if (buy_prob >= buy_thresholds[i] && new_prob >= buy_thresholds[i]) { sides[i] = "buy"; entry[i] = TRUE; }
	else if (buy_prob <= sell_thresholds[i] && new_prob <= sell_thresholds[i]) { sides[i] = "sell"; entry[i] = FALSE }
	else if (new_prob >= buy_thresholds[i] && last_close > stop_price_up) { sides[i] ="buy"; entry[i] = TRUE }
	else if (new_prob <= sell_thresholds[i] && last_close < stop_price) { sides[i] = "sell"; entry[i] = FALSE } 
	else { sides[i] = "hold"; }
      }
      if (tradebot[i] == "angel") { 
        coin_pctg = NA; usd_pctg=NA;
	py$addOrReplaceInstruction(profile=wallets[i], #Profile name
                            symbol=pairs[i], #Currency pair
                            side=sides[i], #Side
                            targetPrice=1000000, #Price target
                            stopLoss=stop_price, #Stop loss
                            stopLossLimitOrders="F", #T or F -- do you want to use limit orders for stop loss?
                           #if bcuz this depends on the side.
                            marketThreshold=0, #At what price do you want to trigger a market order?
                            marketPercent=0.1, # 0 < marketPercent < 1 -- What percent of the bag do you want to execute in each market order
                            maximumTrade="a", # The maximum USD value that you want to execute in this trade
                            orderDepthTarget=.75, # >0 -- The maximum order depth that you want to add to the order book for each limit order
                            orderDepthSearchRange=10 # 1 <= orderDepthSearchRange <= 50 -- how many of the top orders do you want to evaluate to determine the order depth?
        )
      }
      else if (tradebot[i] == "light") {
	err = FALSE 
      	py_run_string("import ccxt")
	set_credentials(exchange=exchanges[i],wallet=wallets[i],client=client)
	if (exchanges[i] == "coinbase") { 
		exchange = "coinbasepro"
		py_string = paste(exchange, "= ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','password' : '",credentials$passphrase,"',})",sep="")
	}
        else {
	       	exchange = exchanges[i]
	       	py_string = paste(exchange," = ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','password' : '",credentials$passphrase,"',})",sep="")
      	}
        #else if (exchanges[i] == "ftxus") { 
	#	exchange = exchanges[i]
	#	py_string = paste(exchange, " = ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','headers':{'FTXUS-SUBACCOUNT': '",credentials$subaccount,"'},})",sep="")
	#print(py_string)
	#}
	Sys.sleep(0.5)
       	tryCatch({py_run_string(py_string)},error=function(e){Information= c("ERROR SENDING Instruction",py_string," To wallet: ",wallets[i]," error: ",e$message);print(Information);slack_message(Information,channel="#tradebot-error-logs"); Information = "error" })
        if (exchanges[i] == "ftxus") { py_string = paste("fetchBalance  = ",exchange,".fetchBalance({'FTXUS-SUBACCOUNT':'",credentials$subaccount,"'})",sep="") }
	else { py_string = paste("fetchBalance  = ",exchange,".fetchBalance()",sep="") } 
     
	tryCatch({py_run_string(py_string)},error=function(e){Information= c("ERROR SENDING Instruction",py_string," To wallet: ",wallets[i]," error: ",e$message);print(Information)} )
	Sys.sleep(0.5)
	py_string = "usd_available = 0"
	py_run_string(py_string)
	py_string = "usd_available = fetchBalance['USD']['free']"
	#py_run_string(py_string)
	tryCatch({py_run_string(py_string)},error=function(e){
		Information= c("ERROR SENDING Instruction",py_string," To wallet: ",wallets[i], " error: ",e$message);
		print(Information);
		#slack_message(Information,channel="#tradebot-error-logs"); 
		Information = "error";
	})
        #paste price from coinbase
	Sys.sleep(0.5)        
	price = last_close + last_close*0.005
	pair1 = get_trade_currency(pairs[i])
        pair_ccxt = str_replace(pairs[i], "-", "/")
	py_string = "coin_quantity = 0";
        py_run_string(py_string)
       	py_string = paste("coin_quantity = fetchBalance['",pair1,"']['free']",sep="")
	#py_run_string(py_string)
	tryCatch({py_run_string(py_string)},error=function(e){Information= c("ERROR SENDING: Instruction",py_string," To wallet: ",wallets[i]," error: ",e$message);
		print(Information);
		#slack_message(Information,channel="#tradebot-error-logs");
		Information = "error" })
	coin_pctg = (py$coin_quantity*last_close)/(py$usd_available + py$coin_quantity*last_close)
	usd_pctg = py$usd_available/(py$coin_quantity*price + py$usd_available)
	total_usd = py$coin_quantity*last_close + py$usd_available
	if (is.nan(coin_pctg)) { coin_pctg = 0 }
	if (is.nan(usd_pctg)) { usd_pctg = 0 }
	if (is.null(total_usd)) { total_usd = 0 }
	else if (is.nan(total_usd)) { total_usd = 0 }
	else if (is.na(total_usd)) { total_usd = 0 }
	print(paste0("Pair: ",pairs[i]," / Coin balance: ", py$coin_quantity, " / USD Available: ",round(py$usd_available,2), "  Asset Price: $", round(price,4)," / Total USD: ",round(total_usd,2)))
	print("---------------------------------------------------")
	#tryCatch({py_run_string(py_string)},error=function(e){Information= c("ERROR SENDING: Instruction",py_string," To wallet: ",wallets[i]);print(Information);slack_message(Information,channel="#tradebot-error-logs"); Information = "error" })
	if (sides[i] == "sell") {
	  py_string = paste("coin_quantity = coin_quantity - coin_quantity*0.005 ",sep="")
          tryCatch({py_run_string(py_string)},error=function(e){
		  Info= c("ERROR SENDING Instruction",py_string," To wallet: ",wallets[i]);
		  print(Info);
		  slack_message(Info,channel="#tradebot-error-logs");
		  #discord(paste0(Info))
		  })
          if (py$coin_quantity*price > 15) {
		if (py$coin_quantity*price*mp[i] > 100) {
		   if (py$coin_quantity*price*mp[i] > max_usd[i]) { py$coin_quantity = solve(price,max_usd[i]) }
	 	   else { py$coin_quantity = py$coin_quantity*mp[i] } 
	    } 
            py_string = paste("MarketSellOrder = ",exchange,".createMarketSellOrder('",pair_ccxt,"',coin_quantity)",sep="") 
            Information = paste(client_info,"Wallet: ",wallets[i], " / Exchange: ",exchanges[i],"/ Model: ", models[i], " / Pair: ",pairs[i]," Timeframe: ",timeframe," Instruction: Market sell quantity: ",round(py$coin_quantity,4)," sent price $",round(last_close,4)," total: $",round(py$coin_quantity*last_close,2),sep="")
            print(Information)
	    tryCatch({py_run_string(py_string)},error=function(e){
		    Info= c("ERROR SENDING: ",Information);
		    print(Info);
		    #discord(Info)
		    slack_message(Info,channel="#tradebot-error-logs") 
		  })
	    Sys.sleep(0.5)
	    #discord(Information)
	    slack_message(Information,channel=trades_channel)
	  }
        }
        else if (sides[i] == "buy") { 
          if (py$usd_available > 15) {	  
            py_string = paste0("coin_quantity = usd_available/",price) 
	    tryCatch({py_run_string(py_string)},error=function(e){
		    Info= c("ERROR SENDING: ",py_string," To wallet: ",wallets[i])
		    print(Info)
		    slack_message(Info,channel="#tradebot-error-logs")
		    #discord(Info)
		}) 
	   if (py$usd_available*mp[i] > 100) {
		   if (py$usd_available*mp[i] <= max_usd[i]) {  py$coin_quantity = py$coin_quantity*mp[i] }
	            else { py$coin_quantity = solve(price,max_usd[i]) }
	   }
	    py_string = paste0("MarketBuyOrder=",exchange,".createMarketBuyOrder('",pair_ccxt,"',coin_quantity)")
            Sys.sleep(0.5)
            Information = paste(client_info,"Wallet: ",wallets[i], " / Exchange: ",exchanges[i],"/ Model: ", models[i], " / Pair: ",pairs[i]," Timeframe: ",timeframe," Instruction: Market buy order quantity: ",round(py$coin_quantity,4)," price: $",round(last_close,4)," total: $",round(py$coin_quantity*last_close,2),sep="")
            print(Information)
	    tryCatch({py_run_string(py_string)},error=function(e){
		    Info = c("ERROR SENDING: ",Information); 
		    #discord(paste0(Info," / error: ",e))
		    slack_message(Info,channel="#tradebot-error-logs")
		})
            Sys.sleep(0.50)
	    #discord(Information)
	    slack_message(Information,channel=trades_channel)	    
	  }
        }
      }
      report_matrix[i,1] = wallets[i]
      report_matrix[i,2] = models[i]
      report_matrix[i,3] = sides[i]
      report_matrix[i,4] = paste(buy_thresholds[i],sell_thresholds[i],sep="/")
      report_matrix[i,5] = round(buy_prob,2)
      report_matrix[i,6] = candle_close[i]
      report_matrix[i,7] = stoploss[i]
      report_matrix[i,8]= paste(round(coin_pctg*100,0),"%",sep="")
      report_matrix[i,9] = total_usd
      Information = paste(client_info,
			  "Exchange: ",exchanges[i],
			  " / Wallet: ",wallets[i],
                          " / Pair: ",pairs[i],
			  " / Model: ",models[i],
                          " / Candles Timeframe: ", timeframe,
                          " / Side: ", sides[i],
                          " / Buy threshold: ",buy_thresholds[i],
                          " / Sell threshold: ",sell_thresholds[i],
			  " / Old Probability:", round(old_buy_prob,2),
                          " / Used Probability:", round(buy_prob,2),
                          " / Wait Candle Close: ", candle_close[i],
                          " / Entry: ",entry[i],
			  " / Stop Loss:", stoploss[i],
			  " / Stop price:", stop_price,
                          " / Coin to USD holdings: ",round(coin_pctg*100,0),"%",
                          " / USD to coin holdings: ",round(usd_pctg*100,0),"%",
      			  " / Total USD: ", round(total_usd,2)
			  ,sep="")
      print(Information)
      print("-----------------------------------------------------------------------------")
      if (old_side != sides[i]) {
        slack_message(Information,channel=channel)
      }
   }
  if (report) { 
	  n_col = ncol(report_matrix)
	  n_row = nrow(report_matrix)
	  rownames(report_matrix) = 1:n_row
	  last_column = report_matrix[,n_col]
	  total_sum = sum(as.numeric(last_column))
	  if (is.na(total_sum) || is.nan(total_sum)) { total_sum = 0 }
	  if (total_sum == 0) { report_matrix[,n_col] = 0 }
	  else { report_matrix[,n_col] = paste(round(as.numeric(last_column)/total_sum,4)*100,"%",sep="") }
	  Exchange = exchanges[i]
	  Client = client
	  Subaccounts = report_matrix
	  TotalUSD = paste("$",round(total_sum,2),sep="")
	  if (!is.null(client)) { slackr_bot(Exchange,Client,Subaccounts,TotalUSD,incoming_webhook_url=slack_webhook(channel)) }
          else {  slackr_bot(Exchange,Subaccounts,TotalUSD,incoming_webhook_url=slack_webhook(channel)); }
  }
  report_matrix=c();
  return(sides);
}



























