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
protocol = "base"     #Protocol of your pool (dhedge).
pool = "0x906b3fa71f011eda7643aad064ad5c38015846d1"    #Address of your pool (smart contract address of your pool).
pair = "DHT-USDC"       #The pair to trade.
slippage = 0.3            #The max allowed slippage for each trade.
share = 100             #The percentage of the whole available balance to buy/sell on each trade.
platform = "odos"  #The platform to use to execute the swaps.
max_usd = 1000         #This will overrides the 'share' when the share is bigger than this amount. This is the highest amount of USD per trade allowed to buy/sell.
threshold = 1           #This is the max amount allowed on the other side of the trade. Example if the trade side is BUY and there is more than 1% of the vault in USDC (from new deposits) it will rebalance the pool.

#DHT Price coingecko


#Crossover Strategy Parameters

N_FAST = 4
N_SLOW = 12
RSI_LOW = 35
RSI_HIGH= 65

# STRATEGY IMPLEMENTATION

last_side = "none"

while (1) {
  tryCatch({
  candles <- get_candles_from_coingecko(id="dhedge-dao",day=30,currency="usd")
  print(candles)
  close = Cl(candles)
  n = length(close)
  TREND = rep(0,n)
  EMA_FAST = EMA(close,n=N_FAST)
  EMA_SLOW = EMA(close,n=N_SLOW)
  RSI_FAST = RSI(close,n=N_FAST)
  SIGNALS = (EMA_FAST - EMA_SLOW)/EMA_FAST
  MEDIAN_SIGNALS = median(na.omit(SIGNALS))
  SD_SIGNALS = sd(na.omit(SIGNALS))
  TREND_BUY_THRESHOLD= MEDIAN_SIGNALS + SD_SIGNALS/3
  TREND_SELL_THRESHOLD= MEDIAN_SIGNALS - SD_SIGNALS/3
  for (i in N_SLOW:n) { 
  	if (SIGNALS[i] >= TREND_BUY_THRESHOLD) { TREND[i] = 1 }
  	else if (SIGNALS[i] <= TREND_SELL_THRESHOLD) { TREND[i] = -1 }
  }
  RSI_LOW_INDEX = max(which(RSI_SLOW <= RSI_LOW))
  RSI_HIGH_INDEX = max(which(RSI_SLOW >= RSI_HIGH))
  if (length(RSI_LOW_INDEX) == 0 || RSI_HIGH_INDEX == 0) { 
    RSI_LOW_INDEX = max(which(RSI_FAST <= RSI_LOW))
    RSI_HIGH_INDEX = max(which(RSI_FAST >= RSI_HIGH))
  }
  
  if (length(RSI_LOW_INDEX) > 0 && length(RSI_HIGH_INDEX) > 0) {
    if (RSI_LOW_INDEX < RSI_HIGH_INDEX) { last_extreme = "high" }
    else { last_extreme = "low" }
  } else { last_extreme = "unknown" }
  if (last_extreme == "low") { 
    if (TREND[n] == 1) { side = "long" }
    else if (TREND[n] == -1 && RSI_SLOW[n] < RSI_SLOW[n-1] && (RSI_SLOW[n-1] <= RSI_SLOW[n-2] || RSI_SLOW[n-1] <= RSI_SLOW[n-3])) { side ="neutral" }
    else if (TREND[n] == -1 && RSI_SLOW[n] >= RSI_SLOW[n-1] && (RSI_SLOW[n-1] > RSI_SLOW[n-2] || RSI_SLOW[n-1] >= RSI_SLOW[n-3])) { side ="long" }
    else { side = "hold" }
  } else if (last_extreme == "high") {
    if (TREND[n] == -1) { side = "neutral" }
    else if (TREND[n] == 1 && RSI_SLOW[n] < RSI_SLOW[n-1] && (RSI_SLOW[n-1] <= RSI_SLOW[n-2] || RSI_SLOW[n-1] <= RSI_SLOW[n-3])) { side = "neutral" }
    else if (TREND[n] == 1 && RSI_SLOW[n] >= RSI_SLOW[n-1] && (RSI_SLOW[n-1] > RSI_SLOW[n-2] || RSI_SLOW[n-1] > RSI_SLOW[n-3])) { side = "long" }
    else { side = "hold" }
  } else { side = "hold" }

  msg = paste("pool: ",pool,"/ network: ",network,"/ side: ",side,"/ last_extreme:", last_extreme,"/ RSI_SLOW[n]:",RSI_SLOW[n],"/ TREND[n]:",TREND[n])
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



