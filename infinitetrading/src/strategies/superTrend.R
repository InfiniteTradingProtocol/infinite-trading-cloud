# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# === Strategy Configurations (Index-matched) ===
networks        = c("base", "optimism", "base")
protocols       = c("dhedge",   "dhedge",  "dhedge")
pools           = c("0x03d1a73d66556f0d7ad0e1f57043e866a7c08d6d", "0x6a18000ebd71b79d345f9f9753253ae4fff84e27", "0x0ae4be81cdbbd7a0a0e86ceb8ef9201837ae41b4")
pairs           = c("wstETH-USDC", "WBTC-USDC", "MORPHO-USDC")
candles_pairs   = c("ETH-USD", "BTC-USD", "MORPHO-USD")
timeframes      = c("1d","1d","6h")
slippages       = c(0.5, 0.5, 0.5)
shares          = c(100, 100, 100)
platforms       = c("odos", "odos", "odos")
max_usds        = c(5000, 5000, 5000)
thresholds      = c(1, 1, 1)
# === Strategy Parameters ===
atr_periods     = c(100, 100, 100)
atr_multipliers = c(5, 5, 5)
sma_lens        = c(50, 50, 50)

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)
in_uptrends     <- rep(FALSE, n_strategies)

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("Running strategy ", i, ": ", pairs[i], "\n"))
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles); high <- Hi(candles); low <- Lo(candles)

      # SuperTrend Calculation
      #ATR_OBJECT =  ATR(HLC(candles), n = atr_periods[i])
      #print(head(ATR_OBJECT,2))

      atr_vals <- ATR(HLC(candles), n = atr_periods[i])[,2]
      hl2 <- (high + low) / 2
      upperBand <- hl2 + atr_multipliers[i] * atr_vals
      lowerBand <- hl2 - atr_multipliers[i] * atr_vals

      superTrend <- rep(NA, length(close))
      trendUp <- rep(TRUE, length(close))

      for (j in 2:length(close)) {
        prevST <- ifelse(!is.na(superTrend[j - 1]), superTrend[j - 1], lowerBand[j - 1])
        trendUp[j] <- ifelse(close[j] > prevST, TRUE,
                          ifelse(close[j] < prevST, FALSE, trendUp[j - 1]))
        superTrend[j] <- ifelse(trendUp[j], max(lowerBand[j], prevST), min(upperBand[j], prevST))
      }

      # SMA + Trend Filter
      sma <- SMA(close, n = sma_lens[i])
      isUptrend <- (close > sma)
      uptrendCount <- lag(isUptrend, 0) + lag(isUptrend, 1)
      isUpConfirmed <- uptrendCount == 2
      isDownConfirmed <- (lag(close, 0) < sma & lag(close, 1) < sma)

      newUptrend <- isUpConfirmed & !in_uptrends[i]
      in_uptrends[i] <- ifelse(isUpConfirmed[length(isUpConfirmed)], TRUE,
                             ifelse(isDownConfirmed[length(isDownConfirmed)], FALSE, in_uptrends[i]))

      # Trade Signals
      enterOnNewUptrend <- last(newUptrend, na.rm = TRUE)
      enterOnSuperTrend <- last(close > superTrend & lag(close) <= lag(superTrend) & in_uptrends[i], na.rm = TRUE)
      exitOnSuperTrend <- last(close < superTrend & lag(close) >= lag(superTrend), na.rm = TRUE)
      exitOnDowntrend <- last(isDownConfirmed, na.rm = TRUE)
      # Trade Execution
      if (enterOnNewUptrend || enterOnSuperTrend) {
        cat(paste0("→ Strategy ", i, " - LONG signal\n"))
	if (last_sides[i] != "long") {
		last_sides[i] <- "long"
        	itp_api(endpoint = "setBot", params = list(
          		apiKey = apiKey,
          		protocol = protocols[i],
          		network = networks[i],
          		pool = pools[i],
          		pair = pairs[i],
          		side = "long",
          		max_usd = max_usds[i],
          		slippage = slippages[i],
          		threshold = thresholds[i],
          		share = shares[i],
          		platform = platforms[i]
        	))
	}
      }

      if (exitOnSuperTrend || exitOnDowntrend) {
	      cat(paste0("→ Strategy ", i, " - EXIT signal\n"))
	      if (last_sides[i] != "neutral") {
		last_sides[i] <- "neutral"
        	cat(paste0("→ Strategy ", i, " - EXIT signal\n"))
        	itp_api(endpoint = "setBot", params = list(
          		apiKey = apiKey,
          		protocol = protocols[i],
          		network = networks[i],
          		pool = pools[i],
          		pair = pairs[i],
          		side = "neutral",
          		max_usd = max_usds[i],
          		slippage = slippages[i],
          		threshold = thresholds[i],
          		share = shares[i],
          		platform = platforms[i]
        	))
      	      }
      }
    }, error = function(e) {
      cat(paste0("Error in strategy ", i, ": ", e$message, "\n"))
    })
  }

  Sys.sleep(60*60*6)  # Sleep 6 hours before next cycle
}

