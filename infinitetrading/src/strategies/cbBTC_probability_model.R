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
pool = "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d"    #Address of your pool (smart contract address of your pool).
pair = "cbBTC-USDC"       #The pair to trade.
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
  candles <- get_candles_with_retry(pair = "BTC-USD", numcandles = 300, timeframe = "6h")
  print(candles)
  close = Cl(candles); open = Op(candles); high = Hi(candles)
  EMA_FAST = EMA(close,n=n_fast);
  EMA_FAST1 = EMA(close,n=n_fast -1); 
  EMA_FAST2 = EMA(close,n=n_fast -2); 

  EMA_SLOW = EMA(close,n=n_slow)
  EMA_SLOW1 = EMA(close,n=n_slow -1);
  EMA_SLOW2 = EMA(close,n=n_slow -2);
  
  EMA200 = EMA(close,n=200)
  EMA100 = EMA(close,n=100)
  EMA50 = EMA(close,n=50) 
  
  SIGNAL1 = last(EMA_FAST - EMA_SLOW) > 0
  SIGNAL2 = (first(last(EMA_FAST - EMA_SLOW,2)) > 0)
  
  SIGNAL3 = last(EMA_FAST - EMA_SLOW1) > 0
  SIGNAL4 = (first(last(EMA_FAST - EMA_SLOW1,2)) > 0)

  SIGNAL5 = last(EMA_FAST - EMA_SLOW2) > 0
  SIGNAL6 = (first(last(EMA_FAST - EMA_SLOW2,2)) > 0)
  
  SIGNAL7 = last(EMA_FAST1 - EMA_SLOW) > 0
  SIGNAL8 = (first(last(EMA_FAST1 - EMA_SLOW,2)) > 0)

  SIGNAL9 = last(EMA_FAST1 - EMA_SLOW1) > 0
  SIGNAL10 = (first(last(EMA_FAST1 - EMA_SLOW1,2)) > 0)

  SIGNAL11 = last(EMA_FAST1 - EMA_SLOW2) > 0
  SIGNAL12 = (first(last(EMA_FAST1 - EMA_SLOW2,2)) > 0)

  SIGNAL13 = last(EMA_FAST2 - EMA_SLOW) > 0
  SIGNAL14 = (first(last(EMA_FAST2 - EMA_SLOW,2)) > 0)

  SIGNAL15 = last(EMA_FAST2 - EMA_SLOW1) > 0
  SIGNAL16 = (first(last(EMA_FAST2 - EMA_SLOW1,2)) > 0)

  SIGNAL17 = last(EMA_FAST2 - EMA_SLOW2) > 0
  SIGNAL18 = (first(last(EMA_FAST2 - EMA_SLOW2,2)) > 0)
  previous_close = first(last(close,2))
  SIGNAL19 = last(close) > last(open)
  SIGNAL20 = last(close) > previous_close
  SIGNAL21 = last(close) > last(high)
  SIGNAL22 = SIGNAL19 && (previous_close > first(last(open,2))) #two soldier
  SIGNAL23 = SIGNAL22 && (first(last(close,3)) > first(last(open,3))) ## three soldier
  
  SIGNAL24 = last(close) > last(EMA_FAST)
  SIGNAL25 = last(close) > last(EMA_FAST1)
  SIGNAL26 = last(close) > last(EMA_FAST2)
  
  SIGNAL27 = previous_close > last(EMA_FAST)
  SIGNAL28 = previous_close > last(EMA_FAST1)
  SIGNAL29 = previous_close > last(EMA_FAST2)

  SIGNAL27 = last(close) > last(EMA_SLOW)
  SIGNAL28 = last(close) > last(EMA_SLOW1)
  SIGNAL29 = last(close) > last(EMA_SLOW2)

  SIGNAL30 = previous_close > last(EMA_SLOW)
  SIGNAL31 = previous_close > last(EMA_SLOW1)
  SIGNAL32 = previous_close > last(EMA_SLOW2)

  SIGNAL33 = SIGNAL27 && SIGNAL28 && SIGNAL29

  SIGNAL34 = SIGNAL30 && SIGNAL31 && SIGNAL32

  SIGNAL35 = SIGNAL33 && SIGNAL34

  SIGNAL36 = SIGNAL27 && SIGNAL30

  SIGNAL37 = SIGNAL24 && SIGNAL25 && SIGNAL26

  SIGNAL38 = last(close) > last(EMA200)
  SIGNAL39 = last(close) > last(EMA100)
  SIGNAL40 = last(close) > last(EMA50)

  SIGNAL41 = SIGNAL38 && SIGNAL39 && SIGNAL40
  PROBABILITY_UP = (SIGNAL1 + SIGNAL2 + SIGNAL3 + SIGNAL4 + SIGNAL5 + SIGNAL6 + SIGNAL7 + SIGNAL8 + SIGNAL9 + SIGNAL10 + SIGNAL11 + SIGNAL12 + SIGNAL13 + SIGNAL14 + SIGNAL15 + SIGNAL16 + SIGNAL17 + SIGNAL18 + SIGNAL19 + SIGNAL20 + SIGNAL21 + SIGNAL22 + SIGNAL23 + SIGNAL24 + SIGNAL25 + SIGNAL26 + SIGNAL27 + SIGNAL28 + SIGNAL29 + SIGNAL30 + SIGNAL31 + SIGNAL32 + SIGNAL33 + SIGNAL34 + SIGNAL35 + SIGNAL36 + SIGNAL37 + SIGNAL38 + SIGNAL39 + SIGNAL40+ SIGNAL41)/41

  if (PROBABILITY_UP >= 0.50) { side = "long" } 
  else if (PROBABILITY_UP < 0.10 && last_side == "long") { side = "neutral" }
  else { side = "hold" } 
  print("Probability UP:") 
  print(PROBABILITY_UP)
  print("SIDE:")
  print(side)
  #print(paste("EMA FAST:",n_fast,EMA_FAST,"EMA SLOW:",n_slow,EMA_SLOW, "DIFFERENCE:",last(EMA_FAST-EMA_SLOW),"SIDE:",side))
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

