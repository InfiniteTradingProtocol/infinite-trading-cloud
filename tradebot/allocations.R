######################
## Dr. Clare	    ##
## Infinite Trading ## 
## Copyright 2024   ##
######################


#Dynamic Zeus Pool
#Check if crossovers, changing thresholds words
#Change vanilla backtester code to support dynamical thresholds


while (1) { 
	#defi_pools
	#infinite_bitcoin_trading
	#get zeus probability
	#last_signal_50_30
	#pull_composition from the pool
	allocation_btc = 0;
	buy_thresholds= c(0.50,0.55,0.57,0.60,0.70,0.80,0.80)
	sell_thresholds=c(0.30,0.35,0.37,0.40,0.30,0.20,0.10)
	signals1 = get_signals("ZeusBTC_6h-BTC-USD",buy_thresholds,sell_thresholds,candle_close=FALSE)
        signals2 = get_signals("ZeusBTC_6h-BTC-USD-HA",buy_thresholds,sell_thresholds,candle_close=TRUE)
	#signals can be 0 (sell) or 1 (buy)
	signals = c(signals1,signals2)
	n = length(signals)
	allocations = rep(1/n,n)
	allocation_btc = sum(allocations*signals)
	allocation_usdc = 1-allocation_btc
	set_allocations(pool="0x302424ex0030r9302r90x09",network="polygon",assets=c("WBTC","USDC","USDCN"),allocations=c(allocation_btc,allocation_usdc,0),upper_thresholds=c(0.10,0.05,0.05),lower_thresholds=c(0.10,0.05,0.05))
	pool_composition(pool="0x302424ex0030r9302r90x09",network="polygon",db=TRUE)
}

#hacer la funcion de get_signals in db.R.
#hacer tabla de las signals en MySQL.
#hacer el allocations monitor thread.
#hacer el USDN monitor thread que convierte USDN a USDC.
#terminar el codigo que pica en pedazos la orden de compra.

