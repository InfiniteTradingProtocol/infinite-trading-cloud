
get_20_sma = function(coins,timeframe) { 
	n = length(coins)
	prices = rep(0,n)
	for (i in 1:n) {
		prices[i] = pull db price of coins[i]
	}
	return(prices)
}

rebalance = function(pool,coins=c("BTC","ETH","MATIC"),formula="sortino_marketcap",formula_weights,sd = 0.02,platform="dhedge",network="polygon") { 

	#check if the usd-balance > 0
	pairs = paste0(coins,"-USD")

	#allocations = allocations_formula(coins,formula,formula_weights)
	allocations = c(0.40,0.40,0.10)
	pool_composition()
	total_usd = get_total_usd(pool)
	n = length(coins) 
	pool_coin_balances = coin_balances(pool)

	#pool_coin_prices = get_20_sma(coins,timeframe="1d") 
	pool_coin_prices= c(22000,1500,1.10)

	pool_usd_balances = pool_coin_prices*pool_coin_balances
	pool_total_usd_balance = sum(pool_usd_balances(pool))
	coin_balance = rep(0,n)
	for (i in 1:n) { 
		coin_balance[i] =
		balance_diff[i] = actual_balance - target_balance
	}
	for (i in 1:n) { 
		if (balance_diff[i]/b > 100) {
				share = solve(usd_allocation,alloc_diff[i])
				amount_to_sell = 
				if (platform == "dhedge") { dhedge_tradebot(pool=pool,side="sell",amount = amount_to_sell,pair=pair); Sys.sleep(0.5) }
				usd_allocation = usd_allocation + share
		} 
	}
	#obtain usd allocation here
	for (i in 1:n) { 
		if (alloc_diff[i] < -sd) { 
				if (actual_allocation[i] == 0) { share = -solve(usd_allocation,alloc_diff[i]) }
				else { share = -alloc_diff[i]/(actual_allocation[i]) }
				if (platform == "dhedge") { dhedge_tradebot(pool=pool,side="buy",share = share,pair=pairs[i]); Sys.sleep(0.5) }
				#recalculate usd allocation
		}
	}
	#pull usd allocation.
	Sys.sleep(0.5)
	for (i in 1:n) { 
		if (alloc_diff[i] > sd) { 
			share = alloc_diff[i]/usd_alloc
			#choose the max of the usd allocation available vs the needed allocation)
			dhedge_tradebot = dhedge_trade(pool=pool,side="buy",share="")
		}
	}
	Sys.sleep(sleep)
}	

