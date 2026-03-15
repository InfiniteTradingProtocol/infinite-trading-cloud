# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# === Strategy Configurations (Index-matched) ===
networks        = c("base","optimism","base","optimism")
protocols       = rep("dhedge",4)
pools           = c("0xa3ff483dcc9791d69d876981b1112269a6ed062d","0x86729853f9cca4c1ec0c160792f36e1bf97d58c3","0x4ce9628fae744c86b3e5435d6777aa4ff2cd15b6","0x9b1a83432996e4e075dd24d4ed7288a2c4ca730a")
pairs           = c("MORPHO-USDC","SNX-USDC","AERO-USDC","AAVE-USDC")
candles_pairs   = c("MORPHO-USD","SNX-USD","AERO-USD","AAVE-USD")
timeframes	= c("6h","6h","6h","6h")
slippages       = c(0.5,0.5,0.5,0.5)
shares          = c(100,100,100,100)
platforms       = c("odos","odos","odos","odos")
max_usds        = c(5000,5000,5000,5000)
thresholds      = c(1,1,1,1)
# === Strategy Parameters ===
ema_fast 	= c(9,10,11,12,13)
ema_slow	= c(29,30,31,32,33)

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("Running strategy ", i, ": ", pairs[i], "\n"))
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles); high <- Hi(candles); low <- Lo(candles)
      signal = 0; n_strats = length(ema_fast)*length(ema_slow)
      for (j in 1:length(ema_fast)) {
      	for (k in 1:length(ema_slow)) {
		EMA_FAST = EMA(close,n=ema_fast[j])
		EMA_SLOW = EMA(close,n=ema_slow[k])
		signal = signal + ifelse(last(EMA_FAST) > last(EMA_SLOW),1,0)
	}
      }
      probability = signal/n_strats
      if (probability >= 0.30) { side = "long" }
      else if (probability >0) { side = "hold" }
      else { side = "neutral" }
      print(paste("signal:",signal))
      print(paste("probability:",probability))
      print(paste("side:",side)) 
      if (last_sides[i] != side) { 
      	itp_api(endpoint = "setBot", params = list(
          apiKey = apiKey,
          protocol = protocols[i],
          network = networks[i],
          pool = pools[i],
          pair = pairs[i],
          side = side,
          max_usd = max_usds[i],
          slippage = slippages[i],
          threshold = thresholds[i],
          share = shares[i],
          platform = platforms[i]
        ))
      }
    }, error = function(e) {
      cat(paste0("Error in strategy ", i, ": ", e$message, "\n"))
    })
  }
  Sys.sleep(60*15)  # Sleep 15 mins before next cycle
}

