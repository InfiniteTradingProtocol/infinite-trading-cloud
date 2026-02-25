source("~/infinitetrading/src/strategies/main.R")

# CONFIGURATION
network <- "optimism"
protocol <- "dhedge"
pool <- "0x"
pair <- "weETH-USDC"
slippage <- 0.3
share <- 100
platform <- "odos"
max_usd <- 10000
threshold <- 1

# STRATEGY PARAMETERS
n_rsi <- 14
rsi_low <- 40
rsi_high <- 60
ema_fast <- 20
ema_slow <- 100

last_side <- "default"

while (1) {
  tryCatch({

    candles <- get_candles_with_retry(pair = "ETH-USD", numcandles = 300, timeframe = "1d")
    close_prices <- Cl(candles)

    # Indicators
    rsi <- RSI(close_prices, n = n_rsi)
    ema12 <- EMA(close_prices, n = ema_fast)
    ema26 <- EMA(close_prices, n = ema_slow)

    # Using current live candle values (last row of real-time feed)
    idx <- nrow(candles)
    current_rsi <- rsi[idx]
    previous_rsi <- rsi[idx - 1]
    previous2_rsi <- rsi[idx - 2]

    current_price <- close_prices[idx]
    ema_fast_now <- ema12[idx]
    ema_slow_now <- ema26[idx]
    ema_fast_prev <- ema12[idx - 1]
    ema_slow_prev <- ema26[idx - 1]

    # Crossover logic
    bullish_crossover <- ema_fast_prev > ema_slow_prev && ema_fast_now > ema_slow_now
    bearish_crossover <- ema_fast_prev < ema_slow_prev && ema_fast_now < ema_slow_now

    # RSI trend check
    rsi_trend_up <- (current_rsi > previous_rsi) && (previous_rsi > previous2_rsi)
    rsi_trend_down <- (current_rsi < previous_rsi) && (previous_rsi < previous2_rsi)

    # Decision logic
    if (!is.na(current_rsi) && !is.na(ema_fast_now) && !is.na(ema_slow_now)) {

      if (current_rsi > rsi_low && ema_fast_now > ema_slow_now && bullish_crossover && rsi_trend_up) {
        side <- "long"
      } else if (current_rsi < rsi_high && ema_fast_now < ema_slow_now && bearish_crossover && rsi_trend_down) {
        side <- "neutral"  # Rebalance to USD
      } else {
        side <- "hold"  # Stay in current state
      }

      print(paste("SIDE:", side,
                  "| RSI:", round(current_rsi, 2),
                  "| EMA12:", round(ema_fast_now, 2),
                  "| EMA26:", round(ema_slow_now, 2),
                  "| CROSSOVER:", ifelse(bullish_crossover, "Bullish", ifelse(bearish_crossover, "Bearish", "None"))
      ))

      if (side != last_side) {
        last_side <- side
        itp_api(endpoint = "setBot", params = list(
          apiKey = apiKey,
          protocol = protocol,
          network = network,
          pool = pool,
          pair = pair,
          side = side,
          max_usd = max_usd,
          slippage = slippage,
          threshold = threshold,
          share = share,
          platform = platform
        ))
      }
    }

  }, error = function(e) {
    print(paste0("Error: ", e$message, " sleeping for 15 minutes..."))
  })

  Sys.sleep(900)  # Wait 15 minutes before next evaluation
}

