
require(reticulate)
require(lubridate)

source("~/infinitetrading/src/tradebot/defi.R")
source("~/infinitetrading/src/slack.R")
calculateIndex <- function(balances, prices, target) {
  if (length(balances) != length(prices) || length(balances) != length(target)) {
    stop("Input lists must have the same length")
  }
  total_value <- sum(balances * prices)
  current_alloc <- (balances * prices) / total_value
  target_alloc <- target / sum(target)
  alloc_diff <- target_alloc - current_alloc
  trade_amounts <- (alloc_diff * total_value) / prices
  return(list(current_alloc = current_alloc,target_alloc = target_alloc,trade_amounts = trade_amounts))
}
rebalance = function(pool,network="polygon",pairs,assets,allocations,protocol="dhedge",composition=NULL,platform="uniswapV3",manager=NULL,slippage=NULL) { 
	last_week = -1
	n = length(pairs)
	if (length(platform) == 1) { platform = rep(platform,n) }
	if (is.null(slippage) || length(slippage) == 1) { slippage = rep(0.5,n) }
	if (is.null(composition)) { composition = pool_comp(pool,network=network,protocol=protocol) }
        if (is.null(ncol(composition))) { 
		discord(paste0("Error: failed to load the pool composition for rebalancing this pool: ", pool, " / network: ",network),db=FALSE)
	}
        else {
		this_week = week(Sys.time())
       		prices = rep(0,n); balances = rep(0,n)
		for (i in 1:n) { 	
			print(paste0("pulling prices for pool:",pool," / pair: ",pairs[i]))
			if (protocol == "dhedge") {
				prices[i] = get_usd_price(assets[i],composition)
			}
			else if (protocol == "defund") {
				if (pairs[i] == "USD-USD") { prices[i] = 1 }
				else { prices[i] = get_price(pairs[i]) }
			}
			print(paste0("pulling balances from composition for: ", pool))
			balances[i] = get_balance(composition,asset=assets[i])	
		}
		composition = pool_comp(pool,network=network,protocol=protocol)
		print(paste0("pairs: ",pairs," / target: ", allocations, " / prices: ",prices))
		print("pool composition"); print(composition) 
		results <- calculateIndex(balances, prices, allocations)
		cat("Current allocation:", sprintf("%.2f", results$current_alloc * 100), "%\n")
		cat("Target allocation:", sprintf("%.2f", results$target_alloc * 100), "%\n")
		cat("Trade amounts:", results$trade_amounts, "\n")
		usdc_alloc = get_allocation(asset="USDC",assets=assets,composition=composition,prices=prices)
		usdc_index = which(assets == "USDC")
		usdc_balance = get_balance(composition,asset="USDC")

		if (length(usdc_index) == 0) { usdc_target_alloc = 0 }
		else { usdc_target_alloc = allocations[usdc_index] }
		print(paste0("USDC allocation: ",usdc_alloc)); print(paste0("USDC target allocation: ",usdc_target_alloc)); print(paste0("USDC balance: ",usdc_balance))
		if (protocol == "dhedge") { 
			#selling every asset
			share = 0
			for (i in 1:n) { 
				if (balances[i] == 0) { share = 0 }
				else { share = ceiling(max(results$trade_amounts[i]/balances[i],-1)*100) }
				print(paste0("asset: ",assets[i]," / share: ", share))
				if ((share < 1) && (assets[i] != "USDC") && (balances[i]*prices[i] > 0)) { 
					if (assets[i] == "USDmny" || assets[i] == "ETHBEAR1X" || assets[i] == "ETHy" || assets[i] == "BTCBEAR1X" || assets[i] == "MATICBEAR1X") { platform = "toros" }
					else { platform = platform[i] }
					trade(from=assets[i],to="USDC",slippage=slippage[i],network=network,pool=pool,platform=platform,share=share*(-1),manager=manager)
					
				}
				Sys.sleep(1)
			}
			Sys.sleep(5)
			#re-calculating the pool composition
			composition = pool_comp(pool,network=network,protocol=protocol)
        		if (is.null(ncol(composition))) {
                		discord(paste0("Error: (trying again) failed to load the pool composition for rebalancing this pool: ", pool, " / network: ",network),db=FALSE)
        			composition = pool_comp(pool,network=network,protocol=protocol)
			}
			#recalculating usdc allocations
			usdc_alloc = get_allocation(asset="USDC",assets=assets,composition=composition,prices=prices)
                	usdc_index = which(assets == "USDC")
                	if (length(usdc_index) == 0) { usdc_target_alloc = 0 }
                	else { usdc_target_alloc = allocations[usdc_index] }
                	print(paste0("USDC allocation: ",usdc_alloc))
                	print(paste0("USDC target allocation: ",usdc_target_alloc))

                	usdc_balance = get_balance(composition,asset="USDC")
                	print(paste0("USDC balance: ",usdc_balance))
			share = 0
			for (i in 1:n) { 
				trade_amount = results$trade_amounts[i]
				if (assets[i] == "USDmny" || assets[i] == "BTCBEAR1X" || assets[i] == "ETHBEAR1X" || assets[i] == "ETHy" || assets[i] == "MATICBEAR1X") { platform="toros" }
				else { platform = platform[i] } 
				trade=FALSE
				if (usdc_balance == 0) { share = 0 }
				else { share = floor(min((trade_amount*prices[i])/usdc_balance,1)*100) }
				print(paste0("asset: ",assets[i]," / share: ", share))
				if ((share > 1) && (assets[i] != "USDC") && (trade_amount*prices[i] > 0) && (usdc_balance > 0)) { 
					trade(from="USDC",to=assets[i],platform=platform,slippage=slippage[i],network=network,pool=pool,share=share,protocol=protocol,manager=manager)
					trade = TRUE; Sys.sleep(60)
					#if (assets[i] == "stMATIC") {
					#	buy_dhedge(from="USDC",to=assets[i],slippage=0.1,platform=platform,network=network,pool=pool,share=share,protocol=protocol)
					#}
				}
				if (trade) { 
			        	composition = pool_comp(pool,network=network,protocol=protocol)
                        		if (is.null(ncol(composition))) {
                                		discord(paste0("Error: (trying again) failed to load the pool composition for rebalancing this pool: ", pool, " / network: ",network),db=FALSE)
                                	composition = pool_comp(pool,network=network,protocol=protocol)
                        		}
                        		#recalculating usdc allocations
                        		usdc_alloc = get_allocation(asset="USDC",assets=assets,composition=composition,prices=prices)
                        		usdc_index = which(assets == "USDC")
                       	 		if (length(usdc_index) == 0) { usdc_target_alloc = 0 }
                        		else { usdc_target_alloc = allocations[usdc_index] }
                        		print(paste0("USDC allocation: ",usdc_alloc))
                        		print(paste0("USDC target allocation: ",usdc_target_alloc))
                        		usdc_balance = get_balance(composition,asset="USDC")
                        		print(paste0("USDC balance: ",usdc_balance))
				}
			}
		}
	}
}

last_week = -1
index_thread = function() {
	#while (1) { 
		this_week = week(Sys.time())
		#DeFi 100x Pool
		pool = "0x31e109968aa38542c4d9efb9a2daa34b442efa44"; network = "polygon"; protocol = "dhedge"
		platform = 'uniswapV3'
		assets = c("DHT","CRV","SNX","LINK","stMATIC","MATICBEAR1X","GRT","GNS","LDO","USDC")
		pairs = paste0(assets,"-USD")
		#later use the allocations formula for this v
		allocations <- c(0.25, 0.10, 0.10, 0.10, 0.10,0.10,0.05,0.05,0.05,0)
		composition = pool_comp(pool,network=network,protocol=protocol)
		usdc_balance = get_balance(composition,asset="USDC")
		if (this_week != last_week || as.numeric(usdc_balance) >= 60) { 
			rebalance(pool=pool,manager="infinitetrading",network=network,protocol=protocol,platform=platform,pairs=pairs,assets=assets,allocations=allocations,composition=composition) 	
			if (last_week != this_week) { last_week = this_week }
		}

		##Defi 100X Pool (Optimism)

		#pool = "0xfbbdcc431a2a45e429574fe04a5fa8a1aa5ba9c0"; network = "optimism"; protocol = "dhedge"
        	#pairs = c("DHT-USD","STG-USD","LYRA-USD","SNX-USD","OP-USD","KWENTA-USD","VELO-USD","USD-USD","USD-USD")
        	#assets = c("DHT","CRV","SNX","LINK","stMATIC","GRT","USDmny","USDC")
        	##later use the allocations formula for this
        	#allocations <- c(0.1428, 0.1428, 0.1428, 0.1428, 0.1428,0.1428,0.1428,0,0)
        	#composition = pool_comp(pool,network=network,protocol=protocol)
        	#usdc_balance = get_balance(composition,asset="USDC")
        	#if (this_week != last_week || as.numeric(usdc_balance) >= 60) {
               # 	rebalance(pool=pool,network=network,protocol=protocol,pairs=pairs,assets=assets,allocations=allocations,composition=composition)
               # 	if (last_week != this_week) { last_week = this_week }
        #	}
	#	Sys.sleep(60*60)
	#}
}
#index_thread()
matic_delta_neutral = function() { 
	pool = "0xc3ffa8d537e31ebf83e7f5f43b481c8101545352"; network = "polygon"; platform = "1inch"; protocol = "dhedge"
	pairs = c("stMATIC-USD","MATICBEAR1X-USD","USDC-USD","USDCN-USD")
	assets = c("stMATIC","MATICBEAR1X","USDC","USDCN")
	allocations = c(0.50,0.50,0,0)
	composition = pool_comp(pool,network=network,protocol=protocol)
	rebalance(pool=pool,network=network,manager="infinitetrading",protocol=protocol,pairs=pairs,slippage=0.05,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
ethy_btc_delta_neutral = function() { 
        pool = "0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c"; network = "optimism"; platform = "uniswapV3"; protocol = "dhedge"
        pairs = c("ETHy-USD","ETHBEAR1X-USD","WBTC-USD","BTCBEAR1X-USD","USDC-USD")
        assets = c("ETHy","ETHBEAR1X","WBTC","BTCBEAR1X","USDC")
        allocations = c(0.50,0.50,0.50,0.50,0)
        composition = pool_comp(pool,network=network,protocol=protocol)
        rebalance(pool=pool,network=network,protocol=protocol,pairs=pairs,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
inflation_hedge = function() {
    	pool = "0xd8e1ed48f2ff726642e1caeae2dafc8a2f9aef01"; network = "polygon"; platform = "uniswapV3"; protocol = "dhedge"
       	pairs = c("stMATIC-USD","MATICBEAR1X-USD","USDC-USD")
       	assets = c("stMATIC","MATICBEAR1X","USDC")
       	allocations = c(0.50,0.50,0)
       	composition = pool_comp(pool,network=network,protocol=protocol)
       	rebalance(pool=pool,network=network,manager="infinitetrading",protocol=protocol,pairs=pairs,slippage=1,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
defi_100x = function() {
	pool = "0x31e109968aa38542c4d9efb9a2daa34b442efa44"; network = "polygon"; platform = "uniswapV3"; protocol = "dhedge"
        pairs = c("DHT-USD","UNI-USD","SNX-USD","CRV-USD","stMATIC-USD","GRT-USD","LINK-USD","LDO-USD","GNS-USD","USDC-USD")
        assets = c("DHT","UNI","SNX","CRV","stMATIC","GRT","LINK","LDO","GNS","USDC")
        allocations = c(0.25,0.08,0.08,0.09,0.08,0.08,0.08,0.08,0.8,0.10)
        composition = pool_comp(pool,network=network,protocol=protocol)
	print(composition)
        rebalance(pool=pool,network=network,protocol=protocol,pairs=pairs,slippage=0.1,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
infinite_btc = function() {
        pool = "0xc3f232c00ab6ce31a332126331da3f74ca1d51cc"; network = "optimism"; platform = "uniswapV3"; protocol = "dhedge"
        pairs = c("WBTC-USD","BTCBEAR1X-USD","USDC-USD")
        assets = c("WBTC","BTCBEAR1X","USDC")
        allocations = c(0.50,0.50,0)
        composition = pool_comp(pool,network=network,protocol=protocol)
        print(composition)
        rebalance(pool=pool,network=network,protocol=protocol,manager="infinitetrading",pairs=pairs,slippage=0.1,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
deltaneutral = function() {
        pool = "0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c"; network = "optimism"; platform = "uniswapV3"; protocol = "dhedge"
        pairs = c("WSTETH-USD","ETHBEAR1X-USD","USDC-USD")
        assets = c("WSTETH","ETHBEAR1X","USDC")
        allocations = c(0.50,0.50,0)
        composition = pool_comp(pool,network=network,protocol=protocol)
        print(composition)
        rebalance(pool=pool,network=network,protocol=protocol,pairs=pairs,slippage=0.1,manager="infinitetrading",assets=assets,platform=platform,allocations=allocations,composition=composition)
}
defi100x = function() {
        pool = "0x31e109968aa38542c4d9efb9a2daa34b442efa44"; network = "polygon"; platform = "uniswapV3"; protocol = "dhedge"
        pairs = c("stMATIC-USD","MATICBEAR1X-USD","USDC-USD")
        assets = c("stMATIC","MATICBEAR1X","USDC")
        allocations = c(0.50,0.50,0)
        composition = pool_comp(pool,network=network,protocol=protocol)
        rebalance(pool=pool,network=network,manager="infinitetrading",protocol=protocol,pairs=pairs,slippage=1,assets=assets,platform=platform,allocations=allocations,composition=composition)
}
defi100x()
#deltaneutral()
#infinite_btc()
#defi_100x()
#matic_delta_neutral()
#ethy_btc_delta_neutral()
#inflation_hedge()
