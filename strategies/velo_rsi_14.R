#--------------------------------------------------------------------------------
# READ THIS IF YOU ARE USING THIS FOR THE FIRST TIME
#
#If this is the first time and you don't have those R packages already installed
#Use install.packages(c("httr","jsonlite","lubridate","TTR","quantmod")) 
#
# 1. Create your dHEDGE vault on dHEDGE.org
#
# 2. Create your gas wallet and api key on our API Site: http://api.infinitetrading.io
#
# 3. Send gas $1 of ETH (Optimism/Arbitrum/Base) or POL (Polygon)) to your gas wallet
#
# 4. Set on your dHEDGE vault the gas wallet address as a 'trader'
#    Go to your vaults on dHEDGE.org click the vault and 'manage' then 'set trader'.
#
# 5. Link your gas wallet to your pool using your apiKeys on the API Site.
#    using the linkGasWallet endpoint.
#
# 6. Use the 'approve' endpoint on the API site and approve both the token to trade and USDC on 'uniswapV3'.
#    For example if your pair is WETH-USDC you have to approve WETH and USDC on two separate calls.
#
# You are set, now you only need to run this code from your server/computer.
# This code will run forever on an infinite loop.
#--------------------------------------------------------------------------------


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
pool = "0x229523504931605f5f654f7346d3d3a2978d951b"    #Address of your pool (smart contract address of your pool).
pair = "VELO-USDC"       #The pair to trade.
slippage = 0.3            #The max allowed slippage for each trade.
share = 100             #The percentage of the whole available balance to buy/sell on each trade.
platform = "odos"  #The platform to use to execute the swaps.
max_usd = 10000         #This will overrides the 'share' when the share is bigger than this amount. This is the highest amount of USD per trade allowed to buy/sell.
threshold = 1           #This is the max amount allowed on the other side of the trade. Example if the trade side is BUY and there is more than 1% of the vault in USDC (from new deposits) it will rebalance the pool.

#Crossover Strategy Parameters

n_rsi=14    
rsi_low=30 
rsi_low_sell = 25
rsi_high=70
rsi_high_sell = 50
# STRATEGY IMPLEMENTATION

last_side = "none"
while (1) {
  tryCatch({
  candles <- get_candles_with_retry(pair = "VELO-USD", numcandles = 300, timeframe = "15m")
  print(candles)
 
  RSI_14 = RSI(Cl(candles),n=14);
  print(RSI_14)
  CURRENT_RSI =last(RSI_14)
  PREVIOUS_RSI = first(last(RSI_14,2))
  PREVIOUS_RSI2 = first(last(RSI_14,3)) 
  RSI_OLD_TREND = ifelse(PREVIOUS_RSI2 > PREVIOUS_RSI,0,1)
  RSI_TREND = ifelse(RSI_OLD_TREND && (CURRENT_RSI < PREVIOUS_RSI || CURRENT_RSI < PREVIOUS_RSI2), 0,1)

  RSI_LOW_INDEX = max(which(RSI_14 <= rsi_low))
  RSI_HIGH_INDEX = max(which(RSI_14 >= rsi_high))
  
  if (RSI_LOW_INDEX < RSI_HIGH_INDEX) { last_extreme = "high" }
  else { last_extreme = "low" } 
  
  if (last_extreme == "low") { 
  	if ((PREVIOUS_RSI < rsi_low || PREVIOUS_RSI2 < rsi_low) && (CURRENT_RSI < rsi_low) && !RSI_TREND) { side = "neutral" }
	else { side = "long" }
  }
  else if (last_extreme == "high") {
	if ( CURRENT_RSI >= rsi_high && RSI_TREND && (PREVIOUS_RSI >= rsi_high) ) { side = "long" }
  	if ( (PREVIOUS_RSI < rsi_high || PREVIOUS_RSI2 < rsi_high) && (CURRENT_RSI < rsi_high) && !RSI_TREND) { side = "neutral" }
 	else { side = "hold" }
  }
  else { side = "hold" }
  msg = paste("pool: ",pool,"/ network: ",network,"/ side: ",side,"/ current RSI:",round(CURRENT_RSI,2))
  print(msg); discord(msg)
  msg = paste("last extreme:",last_extreme,"/ previous RSI:",round(PREVIOUS_RSI,2),"/ previous 2 RSI",round(PREVIOUS_RSI2,2),"/ RSI trend:",ifelse(RSI_TREND,"up","down"), "/ sell low RSI:",rsi_low_sell, "/ sell high RSI: ",rsi_high_sell)
  print(msg); discord(msg) 
  if (side != last_side) { 
      last_side = side
      itp_api(endpoint="setBot",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool,pair=pair,side=side,max_usd=max_usd,slippage=slippage,threshold=threshold,share=share,platform=platform))
  }
  }
  ,error = function(e) { 
    print(paste0("Error: ", e$message, " sleeping for 5 minutes to try again"))
  })
  #sleep for 5 minutes
  Sys.sleep(300)
}

