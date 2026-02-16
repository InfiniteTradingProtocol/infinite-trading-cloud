#dhedge tradebot
require(httr)
require(slackr)
require(stringr)
require(jsonlite)

ref = function(files) { 
	for (i in 1:length(files)) {  
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
	file = paste0(wd,files[i])
	print(paste0("Loading: ",file))
	source(file)
	}
}

ref(c("slack.R","tradebot/web3.R","tradebot/defi.R"))

#how to obtain a key for another pool: https://us-central1-dhedge-trading.cloudfunctions.net/createAccount?pool=[YOUR_POOL_ADDRESS] 

get_row = function(comp,symbol) { 
	n_col = ncol(comp)
	if (length(n_col) > 0) { 
		if (n_col >= 4) return(which(comp[,4] == symbol))
		else return(integer(0)) 
	} 
	else { return(integer(0)) }
}

get_balance = function(comp,symbol,protocol="dhedge") { 
	row_n = get_row(comp,symbol); n_col = ncol(comp)
	balance = 0
	if (length(row_n) == 1) {
		if (!is.null(n_col)) {
	        	if (n_col >= 5) {
				balance = comp[row_n,5]
				if (length(balance) == 1) balance = as.numeric(balance)
				else balance = 0
			}
		}
	}
	return(balance)
}

#comp = pool_comp(pool="0xb990f805c16b65eb9400a390fd9087e4a249e681",network="polygon",db=TRUE)
#get_row(comp,symbol="LINK")
#get_balance(comp,symbol="LINK")
#get_balance(comp,symbol="USDC")

tradebot = function(pool,pair,share=100,slippage=0.5,threshold=0.1,side,price,ep="local",discord=FALSE,platform="1inch",network="polygon",protocol="dhedge",pool_composition=NULL,max_usd=NULL,manager=NULL,apiKey=NULL) {
	trade_currency=strsplit(pair,split="-")[[1]][1]; base_currency = strsplit(pair,split="-")[[1]][2]
	if (side == "buy" || side == "long") { from = base_currency; to = trade_currency } 
	else if (side == "sell" || side == "hold" || side == "short") { from = trade_currency; to = base_currency }
	if (is.null(pool_composition)) { pool_composition = pool_comp(pool=pool,network=network,protocol=protocol); Sys.sleep(1) }
	n_col_comp = ncol(pool_composition)
	if (length(n_col_comp) == 0) { discord(paste0("Error: failed to load pool composition for: ", pair, " / pool: ", pool, " / network: ",network)) }
	else if (n_col_comp < 5) { discord(paste0("Error: failed to load pool composition for: ", pair, " / pool: ", pool, " / network: ",network)) }
	else { 
		Sys.sleep(2); USDMNY = FALSE; USDPY = FALSE; USDCe = FALSE; 
		print("pool composition:"); print(pool_composition)
		if (protocol == "dhedge") { price = get_usd_price(asset=trade_currency,composition=pool_composition) }
		
		usdc_row = get_row(pool_composition,"USDC"); usdmny_row = get_row(pool_composition,"USDmny"); usdpy_row = get_row(pool_composition,"USDpy");
		
		usdce_row = get_row(pool_composition,"USDCe"); mta_row = get_row(pool_composition,"MTA")
		
		#ethbear2x_row = get_row(pool_composition,"ETHBEAR2X"); btcbear2x_row = get_row(pool_composition,"BTCBEAR2X")
		
		btcbear1x_row = get_row(pool_composition,"BTCBEAR1X"); ethbear1x_row = get_row(pool_composition,"ETHBEAR1X")
		
		btcbull3x_row = get_row(pool_composition,"BTCBULL3X"); ethbull3x_row = get_row(pool_composition,"ETHBULL3X")
		wmatic_row = get_row(pool_composition,"WMATIC"); weth_row = get_row(pool_composition,"WETH"); wbtc_row = get_row(pool_composition,"WBTC")
	        ethy_row = get_row(pool_composition,"ETHy");
  		
		usd_value = 0; usdmny_value = 0; usdc_value = 0; asset_usd_value = 0; usdpy_value = 0; usdce_value=0; mta_value =0
		ethy_balance = 0; wmatic_balance = 0; eth3xbull_balance = 0; eth1xbear_balance = 0; btc1xbear_balance = 0; btc2xbear_balance = 0; eth2xbear_balance=0; btc3xbull_balance = 0
                weth_balance = 0;
		
		if (length(wmatic_row) > 0 && (toupper(trade_currency) == "MATICX")) {
                        wmatic_balance = as.numeric(pool_composition[wmatic_row,5]);
                        print(paste0("WMATIC Balance:",ethy_balance))
                        if (wmatic_balance > 0) {
                        	if (side == "sell") { trade(protocol="dhedge",ep=ep,from="WMATIC",to="USDC",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) }
				else { trade(protocol="dhedge",ep=ep,from="WMATIC",to="MATICX",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,apiKey=apiKey) }
                                Sys.sleep(1)
                                new_pool_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                        }
                }
		if (length(ethy_row) > 0 && trade_currency == "ETHy" && side == "sell") {
                        ethy_balance = as.numeric(pool_composition[ethy_row,5]);
                        print(paste0("ETH Yield Balance:",ethy_balance))
                        if (ethy_balance > 0) {
                        	trade(protocol="dhedge",ep=ep,from="ETHy",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                Sys.sleep(1)
                                new_pool_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                        }
                }
		if (length(btcbull3x_row) > 0 && trade_currency == "BTCBULL3X" && side == "sell") { 
			btc3xbull_balance = as.numeric(pool_composition[btcbull3x_row,5]);
			print(paste0("BTCBULL 3X Balance:",btc3xbull_balance))
                        if (btc3xbull_balance > 0) {
                        	trade(protocol="dhedge",ep=ep,from="BTCBULL3X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                Sys.sleep(1)
                                new_pool_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                        }
		}
		if (length(ethbull3x_row) > 0 && trade_currency == "ETHBULL3X" && side == "sell") {
                        eth3xbull_balance = as.numeric(pool_composition[ethbull3x_row,5]);
                        print(paste0("ETHBULL 3X Balance:",eth3xbull_balance))
                        if (eth3xbull_balance > 0) {
                        	trade(protocol="dhedge",ep=ep,from="ETHBULL3X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                Sys.sleep(0.5)
				if (length(weth_row) > 0) { 
					weth_balance = as.numeric(pool_composition[weth_row,5]);
					if (weth_balance > 0) { 
						trade(protocol="dhedge",ep=ep,from="WETH",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                        	Sys.sleep(0.5)
					}
				}
                                new_pool_composition=pool_comp(pool=pool,network=network)
                                if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                        }
                }
		
		#if (length(ethbear2x_row) > 0) {
               	#	ethbear2x_balance = as.numeric(pool_composition[ethbear2x_row,5]);
        	#	print(paste0("ETH BEAR 2X Balance:",ethbear2x_balance))
		#	if (ethbear2x_balance > 0) {
		#	       condition_1 = ((trade_currency == "ETHBULL3X" || trade_currency == "WETH") && side == "buy")
		#	       condition_2 =  (trade_currency == "ETHBEAR2X" && side == "sell")
		#	       if (condition_1 || condition_2 )   { 
		#			trade(protocol="dhedge",ep=ep,from="ETHBEAR2X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
		#			Sys.sleep(1) 
		#			new_pool_composition=pool_comp(pool=pool,network=network)
		#			if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
		#	       }
		#	}
		#}
                
		if (length(ethbear1x_row) > 0) {
                        ethbear1x_balance = as.numeric(pool_composition[ethbear1x_row,5]);
                        print(paste0("ETH BEAR 1X Balance:",ethbear1x_balance))
                        if (ethbear1x_balance > 0) {
                               condition_1 = ((trade_currency == "ETHBULL3X" || trade_currency == "WETH") && side == "buy")
                               condition_2 =  (trade_currency == "ETHBEAR1X" && side == "sell")
                               if (condition_1 || condition_2 )   {
                                        trade(protocol="dhedge",ep=ep,from="ETHBEAR1X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                        Sys.sleep(1)
                                        new_pool_composition=pool_comp(pool=pool,network=network)
                                        if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                               }
                        }
                }
		
		#if (length(btcbear2x_row) > 0) {
                #	btcbear2x_balance = as.numeric(pool_composition[btcbear2x_row,5]);
		#	if (btcbear2x_balance > 0) {
		#	       	condition_1 = ((trade_currency == "BTCBULL3X" || trade_currency == "WBTC") &&  side=="buy") 
		#		condition_2 = (trade_currency == "BTCBEAR2X" && side == "sell") 
		#		if (condition_1 || condition_2) { 
		#			trade(protocol="dhedge",from="BTCBEAR2X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
		#			Sys.sleep(1)
		#			new_pool_composition=pool_comp(pool=pool,network=network,protocol=protocol)
		#			if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
		#		}
		#	}
		#}

                if (length(btcbear1x_row) > 0) {
                        btcbear1x_balance = as.numeric(pool_composition[btcbear1x_row,5]);
                        if (btcbear1x_balance > 0) {
                                condition_1 = ((trade_currency == "BTCBULL3X" || trade_currency == "WBTC") &&  side=="buy")
                                condition_2 = (trade_currency == "BTCBEAR1X" && side == "sell")
                                if (condition_1 || condition_2) {
                                        trade(protocol="dhedge",ep=ep,from="BTCBEAR1X",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey)
                                        Sys.sleep(1)
                                        new_pool_composition=pool_comp(pool=pool,network=network,protocol=protocol)
                                        if (!is.null(ncol(new_pool_composition))) { pool_composition = new_pool_composition }
                                }
                        }
                }
		
		if (length(usdc_row) > 0) { usd_value = as.numeric(pool_composition[usdc_row,5]); usdc_value = usd_value }
		
		if (length(usdmny_row) > 0) { 
			usdmny_value = as.numeric(pool_composition[usdmny_row,5]); usd_value = usd_value + usdmny_value
			if (usdmny_value > 1) { USDMNY = TRUE } 
       		}
		
		if (length(usdpy_row) > 0) {
                        usdpy_value = as.numeric(pool_composition[usdpy_row,5]); usd_value = usd_value + usdpy_value
                        if (usdpy_value > 1) { USDPY = TRUE }
                }
		
		if (length(usdce_row) > 0) {
			usdce_value = as.numeric(pool_composition[usdce_row,5]); usd_value = usd_value + usdce_value
                        if (usdce_value > 1) { USDCe = TRUE }
		}
		
		if (length(mta_row) > 0) {
                        mta_value = as.numeric(pool_composition[mta_row,5]); usd_value = usd_value + mta_value
                        if (mta_value > 1) { MTA = TRUE }
                }

		if (from != "MTA" && from != "USDCe" && from != "USDC" && from != "USDmny" && from != "USDpy") { asset = from }
		else { asset = to }
		
		#price = read asset price from DB if available
		row = which(pool_composition[,4] == asset)
		if (length(row) > 0){ asset_usd_value = as.numeric(pool_composition[row,5])*price }
		# I need to pull the dht value from coinmarketcap
		# I need to add the dht min and max allocations.
		# I need to add different models within the same pool
		total_usd = usd_value + asset_usd_value; 
		print(paste0("Total Pool USD Value:",total_usd))
		if (total_usd  == 0) { allocation = 0 }
		else { allocation = asset_usd_value/total_usd }
		
		print(paste0("pair: ",pair," / side: ",side," / from: ",from, " (",coins(from,network=network),")"," / to: ",to," (",coins(to,network=network),")"))
		print(paste0("coin allocation:", allocation," / asset usd value: ", asset_usd_value, " / total usd value (usdc + usdce + usdmny + usdpny): ",usd_value))
		
		if (str_detect(pair,"BEAR") && side == "buy") {	
			allocation = NA
			if (usdc_value > 1) { trade(protocol="dhedge",ep=ep,from="USDC",to=trade_currency,platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) }
			#if (usdce_value > 5) { trade(protocol="dhedge",ep=ep,from="USDCe",to="USDC",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) } 
		
		}
		if ( (side == "sell" || side =="hold")  && (base_currency == "USDmny" || base_currency=="USDpy" || base_currency == "MTA" || base_currency == "DAI") ) { 
			if (usdc_value > 1) { trade(protocol="dhedge",ep=ep,from="USDC",to=base_currency,ifelse(base_currency=="MTA",platform=platform,platform="toros"),network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) } 
			#if (usdce_value > 5) { trade(protocol="dhedge",ep=ep,from="USDCe",to="USDC",platform="uniswapV3",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey) } 
		}
		if (side == "buy" && (base_currency == "MTA" || base_currency == "USDmny" || base_currency == "USDpy")) { 
			if (usdmny_value > 1) { trade(protocol="dhedge",ep=ep,from="USDmny",to="USDC",platform="toros",netoork=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey); }
			if (usdpy_value > 1) { trade(protocol="dhedge",ep=ep,from="USDpy",to="USDC",platform="toros",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey); }
			if (mta_value > 1) { trade(protocol="dhedge",ep=ep,from="MTA",to="USDC",platform="odos",network=network,share=share,slippage=slippage,pool=pool,max_usd=max_usd,manager=manager,apiKey=apiKey); }
			from = "USDC";
			pair = paste0(to,"-USDC")
		}
		if (usdc_value > 1 && side == "buy" && (base_currency == "USDmny" || base_currency == "USDpy" || base_currency == "MTA")) { from = "USDC"; pair = paste0(to,from,sep="-") }
		else if (side == "sell" && (base_currency == "USDpy" || base_currency == "USDmny" || base_currency=="MTA")) { to = "USDC"; pair = paste(trade_currency,to,sep="-") }
		#if (usdce_value > 5 && side == "buy" && (base_currency == "USDmny" || base_currency == "USDpy")) { from = "USDCe"; pair = paste0(to,from,sep="-") }
                #else if (side == "sell" && (base_currency == "USDpy" || base_currency == "USDmny")) {
                #        to = "USDCe"; pair = paste(trade_currency,to,sep="-")
                #}
		#print(paste0("USDCe Value: ",usdce_value))
		
		#if (usdce_value > 5) { buy_dhedge(ep=ep,from="USDCe",to="USDC",platform="uniswapV3",network=network,share=100,slippage=0.01,pool=pool,manager=manager,apiKey=apiKey) } 
		
		if (!is.na(allocation)) {
        		condition1 = ( (allocation < (1-threshold/100)) && (side == "buy"))
			condition2 = (allocation >= threshold/100 && side == "sell")
        		if ( condition1 || condition2 ) {
				print("trading conditions satisfied, entering trading code inside the tradebot function")
				if (str_detect(pair,"BEAR") || str_detect(pair,"BULL") || str_detect(pair,"USDmny") ||  str_detect(pair,"USDpy") || str_detect(pair,"ETHy") ) { platform = "toros" } 
				res = trade(protocol="dhedge",ep=ep,from=from,to=to,composition=pool_composition,share=share,slippage=slippage,network=network,pool=pool,platform=platform,max_usd=max_usd,manager=manager,apiKey=apiKey)
				print(paste0("response from trade function: ",res))
				slack_msg = paste(pair," / ",side," / Slippage: ",slippage," / $",round(price,4)," / ", platform," / ",protocol,sep="")
                        	print(slack_msg); Sys.sleep(0.5)
				discord(slack_msg,channel="#pools-trading") 
				
				#if (!is.null(res)) { 
				#	if (!is.null(res$status)) { 
				#		if (res$status == "success") {
				#			tx_hash = res$msg
				#			tx_status = NULL
				#			if (!is.null(tx_hash)) { tryCatch(tx_status = get_tx_stastus(tx_hash=tx_hash,network=network)) }
				#			Sys.sleep(0.5)
				#			res$tx_status
				#		}
				#	}
				#	print("here2")	
				#	tryCatch(slack_message(res,channel="#trade-logs"))
				#	print(res)
				#}	
			}
			else print("no action needed, dhedgev2 sides are ok")
		}
	}
}
#trade_dhedge(pool="0xbd9717bebb66b805734af9b0c43ec982ec261f68",price=24500,pair="WBTC-USDC",side="buy")
