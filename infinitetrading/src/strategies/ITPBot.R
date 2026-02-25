# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)
library(zoo)

# === Strategy Configurations ===
networks      <- c("optimism", "optimism", "optimism","optimism")
protocols     <- c("dhedge",   "dhedge",   "dhedge","dhedge")
pools         <- c("", "", "", "")
pairs         <- c("BTC-USDC", "wstETH-USDC",     "WBTC-USDC","wstETH-USDC")
candles_pairs <- c("BTC-USD",  "ETH-USD",      "BTC-USD","ETH-USD")
timeframes    <- c("1d",        "1d",          "6h","6h")
slippages     <- c(0.3,         0.5,           0.5,0.05)
shares        <- c(100,         100,           100,100)
platforms     <- c("odos",      "odos",        "odos","odos")
max_usds      <- c(10000,       5000,          5000,5000)
thresholds    <- c(1,           1,             1,1)

# === Strategy Parameters ===
rsi_periods   <- c(14, 14, 14)
sma_periods   <- c(21, 50, 50)

# === State Variables ===
n_strategies  <- length(pairs)
last_sides    <- rep("hold", n_strategies)

# === Rolling helper functions ===
rolling_max <- function(x, n) rollapply(x, width = n, FUN = max, fill = NA, align = "right")
rolling_min <- function(x, n) rollapply(x, width = n, FUN = min, fill = NA, align = "right")

# === MAIN LOOP ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("\n🚀 Running RSI/SMA strategy ", i, " for ", pairs[i], "\n"))
      
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 100, timeframe = timeframes[i])
      n <- NROW(candles)

      close_prices <- Cl(candles)
      open_prices  <- Op(candles)
      high_prices  <- Hi(candles)
      low_prices   <- Lo(candles)

      # === Indicators ===
      sma <- SMA(close_prices, n = sma_periods[i])
      rsi <- RSI(close_prices, n = rsi_periods[i])

      uptrend <- close_prices > sma
      downtrend <- close_prices < sma

      # === Divergence ===
      bearishDiv <- rsi < rolling_max(rsi, 15) & close_prices > rolling_max(close_prices, 15)
      bullishDiv <- rsi > rolling_min(rsi, 15) & close_prices < rolling_min(close_prices, 15)

      # === Candlestick Patterns ===
      bearishEngulfing <- lag(close_prices) > lag(open_prices) &
                          close_prices < open_prices &
                          close_prices < lag(open_prices) &
                          open_prices > lag(close_prices)

      shootingStar <- (high_prices - pmax(close_prices, open_prices)) > 2 * abs(close_prices - open_prices) &
                      (pmin(open_prices, close_prices) - low_prices) < (high_prices - low_prices) * 0.25

      hangingMan <- (high_prices - low_prices) > 3 * abs(open_prices - close_prices) &
                    (close_prices - low_prices) / (high_prices - low_prices + 0.001) < 0.3

      bearishCandle <- bearishEngulfing | shootingStar | hangingMan

      bullishEngulfing <- lag(close_prices) < lag(open_prices) &
                          close_prices > open_prices &
                          close_prices > lag(open_prices) &
                          open_prices < lag(close_prices)

      morningStar <- n > 2 & lag(close_prices, 2) < lag(open_prices, 2) &
                     abs(lag(open_prices) - lag(close_prices)) < (lag(high_prices) - lag(low_prices)) * 0.3 &
                     close_prices > (lag(open_prices, 2) + lag(close_prices, 2)) / 2

      hammer <- (high_prices - low_prices) > 3 * abs(open_prices - close_prices) &
                (close_prices - low_prices) / (high_prices - low_prices + 0.001) > 0.6

      bullishCandle <- bullishEngulfing | morningStar | hammer

      # === Final Logic ===
      rsiBounce <- any(rsi[(n-7):(n-1)] <= 60) && (rsi[n] > 60)
      rsiTop <- (rsi[n] < 80) && any(rsi[(n-7):(n-1)] >= 80)
      rsiBottom <- any(rsi[(n-7):(n-1)] <= 30 & rsi[n] > 30)
      priceNearSMA <- ((close_prices[n] - sma[n]) / sma[n] < 0.015) && ((close_prices[n] - sma[n]) / sma[n] > 0)

      todayDowntrend <- ifelse(close_prices[n] < close_prices[n-1], 1, 0)
      todayUptrend <- ifelse(close_prices[n] > close_prices[n-1], 1, 0)
      inUptrend <- uptrend[n]
      inDowntrend <- downtrend[n]

      longSignal <- FALSE
      neutralSignal <- FALSE

      if (inUptrend) {
        longSignal <- (rsiBounce || priceNearSMA) || (!bearishCandle[n-1] && !bearishCandle[n]) || todayUptrend || (bullishCandle[n] && !bearishCandle[n-1])
        neutralSignal <- (rsiTop || bearishDiv[n] || bearishCandle[n] || bearishCandle[n-1]) && todayDowntrend
      } else if (inDowntrend) {
        longSignal <- ((any(rsi[(n-7):(n-1)] < 30) && (bullishDiv[n] || bullishCandle[n] || bullishCandle[n-1])) && todayUptrend) || rsiBottom
        neutralSignal <- (bearishCandle[n-1] || bearishCandle[n]) && todayDowntrend
      }

      if (longSignal) {
        side <- "long"
      } else if (neutralSignal) {
        side <- "neutral"
      } else {
        side <- "hold"
      }

      # === Logging ===
      msg <- paste(
        "pool:", pools[i], "(", networks[i], ")", "/ side:", side,
        "/ RSI:", round(rsi[n], 2),
        "/ Price:", round(close_prices[n], 5),
        "/ SMA:", round(sma[n], 5),
        "/ Uptrend:", inUptrend, "/ Downtrend:", inDowntrend,
        "/ rsiTop:", rsiTop, "/ rsiBottom:", rsiBottom,
        "/ bullishDiv:", bullishDiv[n], "/ bearishDiv:", bearishDiv[n]
      )

      cat(msg, "\n")
      discord(msg)

      # === API Execution ===
      if (side != last_sides[i]) {
        last_sides[i] <- side
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
      cat(paste0("❌ Error in strategy ", i, " (", pairs[i], "): ", e$message, "\n"))
    })
  }

  cat("Sleeping 6 hours before next run...\n")
  Sys.sleep(60 * 60 * 6)
}

