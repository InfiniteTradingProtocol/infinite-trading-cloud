#dhedge tradebot
require(httr)
# require(slackr)  # Optional - comment out if not installed
require(stringr)
require(jsonlite)

ref = function(files) { 
	for (i in 1:length(files)) {  
	# Use relative path from tradebot/tradebot/
	wd = paste0(dirname(dirname(getwd())), "/")
	file = paste0(wd,files[i])
	print(paste0("Loading: ",file))
	if (file.exists(file)) {
		source(file)
	} else {
		print(paste0("Warning: File not found: ", file))
	}
	}
}

# Comment out files that don't exist yet
# ref(c("slack.R","tradebot/web3.R","tradebot/defi.R"))

#how to obtain a key for another pool: https://us-central1-dhedge-trading.cloudfunctions.net/createAccount?pool=[YOUR_POOL_ADDRESS] 

get_row = function(comp,symbol) { 
	n_col = ncol(comp)
	if (length(n_col) > 0) { 
		if (n_col >= 4) return(which(comp[,4] == symbol))
		else return(integer(0)) 
	} 
	else { return(integer(0)) }
}

get_balance = function(composition=NULL,symbol,protocol="dhedge",bignumber=FALSE)  {	
	asset_row = c(); asset_balance = 0
	if (!is.null(composition)) { asset_row = which(composition[,4] == symbol); }
	if (length(asset_row) > 0) {
		if (!bignumber) asset_balance = as.numeric(composition[asset_row,5])
		else asset_balance = as.numeric(composition[asset_row,6]);
	}
	return(asset_balance)
}
#comp = pool_comp(pool="0xb990f805c16b65eb9400a390fd9087e4a249e681",network="polygon",db=TRUE)
#get_row(comp,symbol="LINK")
#get_balance(comp,symbol="LINK")
#get_balance(comp,symbol="USDC")

#is_btc_bull = function(asset) return((asset %in% c("BTCBULL3X","BTCBULL2X","BTCBULL4X")))
#is_eth_bull = function(asset) return((asset %in% c("ETHBULL3X","ETHBULL2X")))
#is_bull = function(asset) return((is_btc_bull(asset) || is_eth_bull(asset)))
#is_bear = function(asset) return((asset %in% c("ETHBEAR1X","BTCBEAR1X")))
#is_toros

tradebot = function(pool,pair,share=100,slippage=0.5,threshold=0.1,side,price,ep="local",discord=FALSE,platform="1inch",network="polygon",protocol="dhedge",pool_composition=NULL,max_usd=NULL,manager=NULL,apiKey=NULL) {
	trade_currency=strsplit(pair,split="-")[[1]][1]; base_currency = strsplit(pair,split="-")[[1]][2]
	if (side == "buy" || side == "long") { from = base_currency; to = trade_currency } 
	else if (side == "sell" || side == "hold" || side == "short") { from = trade_currency; to = base_currency }
	
	if (is.null(pool_composition)) { pool_composition = pool_comp(pool=pool,network=network,protocol=protocol); Sys.sleep(1) }
	n_col_comp = ncol(pool_composition)
	
	if (length(n_col_comp) == 0) { discord(paste0("Error: failed to load pool composition for: ", pair, " / pool: ", pool, " / network: ",network)) }
	else if (n_col_comp < 5) { discord(paste0("Error: failed to load pool composition for: ", pair, " / pool: ", pool, " / network: ",network)) }
	
	else { 
		Sys.sleep(2);
		print("pool composition:"); print(pool_composition)
		if (protocol == "dhedge") { price = get_usd_price(asset=trade_currency,composition=pool_composition) }
		
		wmatic_row = get_row(pool_composition,"WPOL"); 
		usdc_value = 0; asset_usd_value = 0; wmatic_balance = 0; 
		if (length(wmatic_row) > 0 && (toupper(trade_currency) == "MATICX")) {
                        wmatic_balance = as.numeric(pool_composition[wmatic_row,5]);
                        print(paste0("WPOL Balance:",wmatic_balance))
                        if (wmatic_balance > 0) {
                        	if (side == "sell") { trade(protocol="dhedge",ep=ep,from="WPOL",to="USDC",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) }
				else { trade(protocol="dhedge",ep=ep,from="WPOL",to="MATICX",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,apiKey=apiKey) }
                                Sys.sleep(0.5)
                                new_pool_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                        }
                }
		
		#This part check if you have a sell signal and a trade balance to execute it and check if its a bull token.
		#It also checks if you have an additional balance (WETH or WBTC) to sell it too.
		bear_balance = 0; sell_bear = FALSE
		if (is_eth(trade_currency)) { bear_token = "ETHBEAR1X" }
		else if (is_btc(trade_currency)) { bear_token = "BTCBEAR1X" }
		else { bear_token = NULL }
		if (!is.null(bear_token)) { bear_balance = get_balance(pool_composition,bear_token,protocol) }
		
		usd_value = get_balance(pool_composition,"USDC",protocol=protocol)
		usdc_value = usd_value
		
		trade_balance = get_balance(comp=pool_composition,symbol=trade_currency,protocol=protocol)
		
		if (trade_balance > 0 && side == "sell" && is_bull(trade_currency)) {
			print(paste("Asset:" ,trade_currency,"/ Balance:",trade_balance))
			additional_asset=NULL
			if (is_eth_bull(trade_asset)) { additional_asset = "WETH";} 
		        else if (is_btc_bull(trade_asset)) { additional_asset = "WBTC"; }
			if (!is.null(additional_asset)) { 
				trade(protocol=protocol,ep=ep,from=trade_currency,to=additional_asset,platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
				Sys.sleep(0.5);
                                new_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
				additional_balance = get_balance(pool_composition,additional_asset,protocol)	
				if (additional_balance > 0 && base_currency != additional_asset) { 
					trade(protocol="dhedge",ep=ep,from=additional_asset,to=base_currency,platform=platform,network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
					Sys.sleep(0.5); 
					new_composition=pool_comp(pool=pool,network=network)
					if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
				}
			}
		}
                if (bear_balance > 0) {
			if (!is_bear(trade_currency) && side == "buy") {
			       	if (is_eth(trade_currency) || is_btc(trade_currency) || is_bull(trade_currency)) { sell_bear = TRUE }
			}
			else if (is_bear(trade_currency) && side == "sell")  { sell_bear = TRUE }
		}
                if (sell_bear) {
			if (bear_token == "ETHBEAR1X") { bear_to = "WETH" }
			else if (bear_token == "BTCBEAR1X") { bear_to = "WBTC" }
                	trade(protocol="dhedge",ep=ep,from=bear_token,to="WBTC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                        Sys.sleep(1)
                        new_pool_composition=pool_comp(pool=pool,network=network,protocol=protocol)
                        if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                }
		else if (is_bear(trade_currency) && side == "buy" && usdc_value > 0) { 
		        if (any(short_networks == network)) { 
				additional_asset = NULL
				if (trade_currency == "ETHBEAR1X") { additional_asset = "WETH" }
				else if (trade_currency == "BTCBEAR1X") { additional_asset = "WBTC" }
				
				#If there is the additional asset deposited trade it out

				if (!is.null(additional_asset)) { 
					additional_balance = get_balance(pool_composition,additional_asset,protocol)
					if (additional_balance > 0) { 
						if (additional_asset != base_currency) { 
							trade(protocol="dhedge",ep=ep,from=additional_asset,to=base_currency,platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                			Sys.sleep(0.5)
                                			new_pool_composition=pool_comp(pool=pool,network=network,protocol=protocol)
                                			if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
						}
					}
				}
				
				#Buy everything on the toros token
				trade(protocol="dhedge",ep=ep,from="USDC",to=bear_token,platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                        	Sys.sleep(0.5)
                        	new_pool_composition=pool_comp(pool=pool,network=network,protocol=protocol)
                        	if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
			}
			else { 
				msg = paste0("Error: shorts not enabled on this network: ",network, " / pool: ",pool, " / apiKey: ",apiKey)
				print(msg)
				return(msg)
			}
		}

		#update values
		usd_value = get_balance(pool_composition,"USDC",protocol)	
		usdc_value = usd_value
		trade_balance = get_balance(pool_composition,trade_currency,protocol)
		if (from != "USDC") { asset = from }
		else { asset = to }
		
		asset_usd_value = price*trade_balance
	
		total_usd = usd_value + asset_usd_value; 
		print(paste0("Total Pool USD Value:",total_usd))
		if (total_usd == 0) { allocation = 0 }
		else { allocation = asset_usd_value/total_usd }
		
		print(paste0("pair: ",pair," / side: ",side," / from: ",from, " (",coins(from,network=network),")"," / to: ",to," (",coins(to,network=network),")"))
		print(paste0("coin: ",asset, " / coin allocation:", allocation," / coin usd value: ", asset_usd_value, " / total usdc value: ",usd_value))
		
		
		#IMPLEMENT THIS WITH WETH or WBTC as the BASE CURRENCY!

		#if (usdc_value > 1 && side == "buy" && (base_currency == "USDmny")) { from = "USDC"; pair = paste0(to,from,sep="-") }
		#else if (side == "sell" && (base_currency == "USDpy") { to = "USDC"; pair = paste(trade_currency,to,sep="-") }	
		
		if (!is.na(allocation)) {
        		condition1 = ( (allocation < (1-threshold/100)) && (side == "buy"))
			condition2 = (allocation >= threshold/100 && side == "sell")
       			condition2 = TRUE
			if ( condition1 || condition2 ) {
				
				print("trading conditions satisfied, entering trading code inside the tradebot function")
				
				res = trade(protocol="dhedge",ep=ep,from=from,to=to,composition=pool_composition,share=share,slippage=slippage,network=network,pool=pool,platform=platform,max_usd=max_usd,manager=manager,apiKey=apiKey)
				
				print(paste0("response from trade function: ",res))
				
				#slack_msg = paste(pair," / ",side," / Slippage: ",slippage," / $",round(price,4)," / ", platform," / ",protocol,sep="")
                        	#print(slack_msg); Sys.sleep(0.5)
				#discord(slack_msg,channel="#pools-trading") 	
			}
			else print("All dhedgev2 sides are ok")
		}
	}
}
#trade_dhedge(pool="0xbd9717bebb66b805734af9b0c43ec982ec261f68",price=24500,pair="WBTC-USDC",side="buy")
