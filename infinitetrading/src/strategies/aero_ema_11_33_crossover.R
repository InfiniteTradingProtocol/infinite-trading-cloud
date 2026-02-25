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

#Loading dependencies  
source("~/infinitetrading/src/strategies/main.R")


#Setup and credentials

network = "base"     #Network of your pool (optimism/base/polygon/arbitrum).
protocol = "dhedge"     #Protocol of your pool (dhedge).
pool = "0x640fa02105f58e266d7dd9c16ff06a802087108d"    #Address of your pool (smart contract address of your pool).
pair = "AERO-USDC"       #The pair to trade.
slippage = 0.3            #The max allowed slippage for each trade.
share = 100             #The percentage of the whole available balance to buy/sell on each trade.
platform = "odos"  #The platform to use to execute the swaps.
max_usd = 10000         #This will overrides the 'share' when the share is bigger than this amount. This is the highest amount of USD per trade allowed to buy/sell.
threshold = 1           #This is the max amount allowed on the other side of the trade. Example if the trade side is BUY and there is more than 1% of the vault in USDC (from new deposits) it will rebalance the pool.

#Crossover Strategy Parameters

n_fast=11   #Fast moving average (EMA)
n_slow =33 #Slow moving average (EMA)

# STRATEGY IMPLEMENTATION

last_side = "hold"
while (1) {
  tryCatch({
  candles <- get_candles_with_retry(pair = "AERO-USD", numcandles = 300, timeframe = "6h")
  print(candles)
  EMA_FAST = EMA(Cl(candles),n=n_fast); EMA_SLOW = EMA(Cl(candles),n=n_slow)

  CROSSOVERS = EMA_FAST - EMA_SLOW
  side = ifelse(last(CROSSOVERS)>0,"long","neutral")
  print(paste("EMA FAST:",n_fast,EMA_FAST,"EMA SLOW:",n_slow,EMA_SLOW, "DIFFERENCE:",last(EMA_FAST-EMA_SLOW),"SIDE:",side))
  if (side != last_side) { 
      last_side = side
      itp_api(endpoint="setBot",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool,pair=pair,side=side,max_usd=max_usd,slippage=slippage,threshold=threshold,share=share,platform=platform))  }
  }
  ,error = function(e) { 
    print(paste0("Error: ", e$message, " sleeping for 5 minutes to try again"))
  })
  #sleep for 5 minutes
  Sys.sleep(300)
}

