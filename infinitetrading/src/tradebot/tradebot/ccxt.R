###############################
#Classification CCXT Trade Bot#
# Copyright Tradery Labs 2021 #
# Author: Mr. Richard Clare   #
###############################


wd = "/home/ubuntu/GitHub/Tradery-Development/"
publicSleepInterval = 0.1
#source(paste(wd,"basic.R",sep=""))
require(reticulate);
#source_python(path.expand(paste0(wd,'sendInstruction.py')))
require(quantmod);require(stringr); require(TTR); require(httr); require(rgdax); require(jsonlite); require(lubridate); require(snakecase)
py_run_string("import ccxt")

trade = function(exchange,wallet,client,side,order_type="market",futures = FALSE,sleep=0.1,channel="#trade-logs",errors_channel="#tradebot-error-logs",subaccount=NULL) {
	set_credentials(exchange=exchanges[i],wallet=wallets[i],client=client)
        if (exchanges[i] == "coinbase") {
                exchange = "coinbasepro"
                py_string = paste(exchange, "= ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','password' : '",credentials$passphrase,"',})",sep="")
        }
	else if (futures && exchanges[i] == "binance") {
		py_string = paste(exchange," = ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','enableRateLimit': True, 'options': { 'defaultType': 'future',},})",sep="")	
	}
        else {
                exchange = exchanges[i]
                py_string = paste(exchange," = ccxt.",exchange,"({'apiKey':'",credentials$key,"','secret':'",credentials$secret,"','password' : '",credentials$passphrase,"',})",sep="")
	}
	tryCatch(
		{py_run_string(py_string)},
		error=function(e){
			Information= c("ERROR SENDING Instruction",py_string," To wallet: ",wallets[i]," error: ",e$message)
			print(Information);
			slack_message(Information,channel=errors_channel);
			Information = "error" }
	)
        if (exchanges[i] == "ftxus" && !is.null(subaccount) ) { py_string = paste("fetchBalance  = ",exchange,".fetchBalance({'FTXUS-SUBACCOUNT':'",credentials$subaccount,"'})",sep="") }
        else { py_string = paste("fetchBalance  = ",exchange,".fetchBalance()",sep="") }
        if (side == "sell") {}
	else if (side == "buy") {
        else if (sides[i] == "buy") {
          if (py$usd_available > 10) {
            py_string = paste("coin_quantity = usd_available/",price,sep="")
            tryCatch({py_run_string(py_string)},error=function(e){Information= c("ERROR SENDING: ",py_string," To wallet: ",wallets[i]);print(Information);slack_message(Information,channel="#tradebot-error-logs"); Information = "error" })
           if (py$usd_available*mp[i] > 10) {
                   if (py$usd_available*mp[i] <= max_usd[i]) {  py$coin_quantity = py$coin_quantity*mp[i] }
                    else { py$coin_quantity = solve(price,max_usd[i]) }
           }
            if ()  { 
		py_string = paste("MarketBuyOrder = ",exchange,".createMarketBuyOrder('",pair_ccxt,"',coin_quantity)",sep="")
	    }            
	    Sys.sleep(0.15)
            Information = paste(client_info,"Wallet: ",wallets[i], " / Exchange: ",exchanges[i],"/ Model: ", models[i], " / Pair: ",pairs[i]," Timeframe: ",timeframe," Instruction: Market buy order quantity: ",round(py$coin_quantity,4)," price: $",round(last_close,4)," total: $",round(py$coin_quantity*last_close,2),sep="")
            print(Information)
            tryCatch({py_run_string(py_string)},error=function(e){Information <<- c("ERROR SENDING: ",Information); slack_message(paste(Information,e),channel="#tradebot-error-logs"); Information = "error"})
            Sys.sleep(0.15)
            if (Information != "error") { slack_message(Information,channel=trades_channel) }
          }
        }
      }	
}

