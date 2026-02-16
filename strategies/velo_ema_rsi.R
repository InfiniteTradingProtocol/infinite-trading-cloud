#Loading main functions for strategies
# Dynamic path detection - works in both PM2 and direct execution
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    # Direct execution: script is in strategies/, go up to repo root
    script_dir = dirname(normalizePath(ofile))
    wd = paste0(dirname(script_dir), "/")
  } else {
    # PM2 execution: cwd is already repo root
    script_dir = normalizePath(".")
    # Check if we're already in repo root (has strategies/ folder)
    if (dir.exists("strategies")) {
      wd = paste0(script_dir, "/")
    } else {
      # We're in strategies/ folder, go up one level
      wd = paste0(dirname(script_dir), "/")
    }
  }
}
source(paste0(wd, "strategies/main.R"))


network = "optimism"     #Network of your pool (optimism/base/polygon/arbitrum).
protocol = "dhedge"     #Protocol of your pool (dhedge).
pool = "0x3ea63ff997ac81d6a6753588b967db60b112e520" #Address of your pool (smart contract address of your pool).
pair = "VELO-USDC"       #The pair to trade.
slippage = 0.3            #The max allowed slippage for each trade.
share = 100             #The percentage of the whole available balance to buy/sell on each trade.
platform = "odos"  #The platform to use to execute the swaps.
max_usd = 10000         #This will overrides the 'share' when the share is bigger than this amount. This is the highest amount of USD per trade allowed to buy/sell.
threshold = 1           #This is the max amount allowed on the other side of the trade. Example if the trade side is BUY and there is more than 1% of the vault in USDC (from new deposits) it will rebalance the pool.

# === Parameters ===

rsiPeriod <- 14
rsiOversold_uptrend <- 40
rsiOverbought_uptrend <- 80
emaFastPeriod <- 50
emaSlowPeriod <- 200
rsiOversold_downtrend <- 30
rsiOverbought_downtrend <- 70

last_side = "none"
while (1) {
	candles <- get_candles_with_retry(pair = "VELO-USD", numcandles = 300, timeframe = "15m")

	# === Indicators ===
	close_prices <- Cl(candles)
	n = length(close_prices)

	rsi <- RSI(close_prices, n = rsiPeriod)
	emaFast <- EMA(close_prices, n = emaFastPeriod)
	emaSlow <- EMA(close_prices, n = emaSlowPeriod)


	# === Entry Conditions ===
	longCondition_uptrend <- (rsi[n-1] < rsiOversold_uptrend) & (emaFast[n-1] > emaSlow[n-1]) & (close_prices[n-1] > emaSlow[n-1] & close_prices[n]> emaSlow[n-1])
	longCondition_downtrend <- (rsi[n-1] < rsiOversold_downtrend) & (emaFast[n-1] < emaSlow[n-1]) & (close_prices[n-1] > emaFast[n-1] & close_prices[n] > emaFast[n-1])

	# === Exit Conditions (only closing long trades for now) ===
	shortCondition_uptrend <- (rsi[n-1] > rsiOverbought_uptrend) & (emaFast[n-1] > emaSlow[n-1]) & (close_prices[n-1] < emaFast[n-1] & close_prices[n] < emaFast[n-1])
	shortCondition_downtrend <- (rsi[n-1] > rsiOverbought_downtrend) & (emaFast[n-1] < emaSlow[n-1]) & (close_prices[n-1] > emaFast[n-1] & close_prices[n] < emaFast[n-1])

	# === Strategy Logic ===
	longSignal <- longCondition_uptrend | longCondition_downtrend
	exitSignal <- shortCondition_uptrend | shortCondition_downtrend

	if (longSignal) { side = "long" }
	else if (exitSignal) { side = "neutral" }
	else { side = "hold" }
	decimals = 4
	msg = paste("pool:",pool,"(",network,")","/ side:",side,"/ RSI:",round(rsi[n],2),"/ tick:", round(close_prices[n],decimals),"/ RSI[n-1]:",round(rsi[n-1],2), "/ RSI high up/down trend:",rsiOverbought_uptrend,rsiOverbought_downtrend, "/ RSI low up/down trend: ",rsiOversold_uptrend,rsiOversold_downtrend, "/ EMA fast period:",emaFastPeriod, "/ EMA fast:",round(emaFast[n-1],decimals),"/ EMA slow period:", emaSlowPeriod,"/ EMA slow:",round(emaSlow[n-1],decimals))
  	print(msg); discord(msg)
	if (side != last_side) {
      		last_side = side
      		itp_api(endpoint="setBot",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool,pair=pair,side=side,max_usd=max_usd,slippage=slippage,threshold=threshold,share=share,platform=platform))
  	}
	print(side)
	Sys.sleep(60*5) 
}
