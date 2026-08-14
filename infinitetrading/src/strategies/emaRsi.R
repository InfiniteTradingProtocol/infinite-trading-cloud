#--------------------------------------------------------------------------------
# EMA + RSI Multi-Pair Strategy
#
# This strategy combines EMA crossovers with RSI extremes to identify entry points.
# It can trade multiple pairs simultaneously with different parameters per pair.
#
# Strategy Logic:
# - Uses fast/slow EMA to determine trend direction
# - Uses RSI to identify oversold (buy) and overbought (sell) conditions
# - Only enters long positions when trend is bullish AND RSI shows oversold
# - Exits to neutral when trend reverses or RSI shows overbought
#--------------------------------------------------------------------------------

# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# === Strategy Configurations (Index-matched arrays) ===

# Pool & Network Configuration
networks        = c("optimism")
protocols       = c("dhedge")
pools           = c("0x906b3fa71f011eda7643aad064ad5c38015846d1")
pairs           = c("DHT-USDC")
candles_pairs   = c("ETH-USD")  # Use ETH as proxy since DHT not on Coinbase
timeframes      = c("6h")        # Timeframe: 15m, 1h, 4h, 6h, 1d
data_sources    = c("coinbase") # "coinbase" or "coingecko"

# Trading Parameters
slippages       = c(0.3)         # Max slippage per trade (%)
shares          = c(100)         # Percentage of balance to trade
platforms       = c("odos")      # DEX to use: odos, uniswapV3, etc
max_usds        = c(1000)        # Max USD per trade
thresholds      = c(1)           # Min % on other side to trigger rebalance

# === EMA Parameters (per strategy) ===
# Each strategy can have different EMA periods
ema_fast_list   = list(
  c(4)      # Strategy 1: DHT uses 4-period fast EMA
)

ema_slow_list   = list(
  c(12)     # Strategy 1: DHT uses 12-period slow EMA
)

# === RSI Parameters (per strategy) ===
rsi_periods     = c(4)           # RSI calculation period
rsi_lows        = c(35)          # RSI oversold threshold
rsi_highs       = c(65)          # RSI overbought threshold

# === Signal Thresholds (per strategy) ===
# EMA signal is normalized: (EMA_FAST - EMA_SLOW) / EMA_FAST
# These multipliers adjust trend sensitivity
trend_buy_multipliers  = c(0.33)  # Fraction of 1 std dev above median
trend_sell_multipliers = c(0.33)  # Fraction of 1 std dev below median

# === State Variables ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)

# === Helper Functions ===

# Get candles based on data source
get_strategy_candles <- function(source, pair, candles_pair, days = 30, timeframe = "1d", numcandles = 300) {
  if (source == "coingecko") {
    # For coingecko, extract the coin ID from the pair
    coin_id <- tolower(strsplit(candles_pair, "-")[[1]][1])
    # Map common symbols to coingecko IDs
    if (coin_id == "dht") coin_id <- "dhedge-dao"
    if (coin_id == "weth") coin_id <- "weth"
    if (coin_id == "btc") coin_id <- "bitcoin"

    candles <- get_candles_from_coingecko(id = coin_id, day = days, currency = "usd")
    return(candles)
  } else {
    # Default to coinbase
    candles <- get_candles_with_retry(pair = candles_pair, numcandles = numcandles, timeframe = timeframe)
    return(candles)
  }
}

# Calculate EMA-RSI signals
calculate_ema_rsi_signals <- function(candles, ema_fast_periods, ema_slow_periods,
                                      rsi_period, rsi_low, rsi_high,
                                      trend_buy_mult, trend_sell_mult) {
  close <- Cl(candles)
  n <- length(close)

  # Initialize containers
  all_signals <- numeric(0)

  # Calculate signals for each EMA combination
  for (fast in ema_fast_periods) {
    for (slow in ema_slow_periods) {
      ema_fast_vals <- EMA(close, n = fast)
      ema_slow_vals <- EMA(close, n = slow)

      # Normalized signal: (EMA_FAST - EMA_SLOW) / EMA_FAST
      signals <- (ema_fast_vals - ema_slow_vals) / ema_fast_vals
      all_signals <- c(all_signals, last(signals))
    }
  }

  # Guard against all-NA signals (common with short/invalid series windows)
  finite_signals <- all_signals[is.finite(all_signals)]
  if (length(finite_signals) == 0) {
    return(list(
      side = "hold",
      trend = 0,
      current_rsi = NA,
      last_extreme = "unknown",
      signal_strength = 0,
      trend_buy_threshold = 0,
      trend_sell_threshold = 0
    ))
  }

  # Calculate trend thresholds based on signal distribution
  median_signal <- median(finite_signals)
  sd_signal <- sd(finite_signals)
  if (!is.finite(sd_signal)) sd_signal <- 0

  trend_buy_threshold <- median_signal + (sd_signal * trend_buy_mult)
  trend_sell_threshold <- median_signal - (sd_signal * trend_sell_mult)

  # Determine current trend
  current_signal <- mean(finite_signals)
  if (!is.finite(current_signal)) current_signal <- 0
  if (current_signal >= trend_buy_threshold) {
    trend <- 1  # Bullish
  } else if (current_signal <= trend_sell_threshold) {
    trend <- -1  # Bearish
  } else {
    trend <- 0  # Neutral
  }

  # Calculate RSI
  rsi_vals <- RSI(close, n = rsi_period)

  # Check if we have valid RSI data
  if (all(is.na(rsi_vals))) {
    return(list(
      side = "hold",
      trend = 0,
      current_rsi = NA,
      last_extreme = "unknown",
      signal_strength = 0,
      trend_buy_threshold = 0,
      trend_sell_threshold = 0
    ))
  }

  current_rsi <- last(na.omit(rsi_vals))
  rsi_length <- length(rsi_vals)
  prev_rsi <- if (rsi_length > 1) rsi_vals[rsi_length - 1] else NA
  prev_rsi_2 <- if (rsi_length > 2) rsi_vals[rsi_length - 2] else NA
  prev_rsi_3 <- if (rsi_length > 3) rsi_vals[rsi_length - 3] else NA

  # Find last RSI extreme
  rsi_low_indices <- which(!is.na(rsi_vals) & rsi_vals <= rsi_low)
  rsi_high_indices <- which(!is.na(rsi_vals) & rsi_vals >= rsi_high)

  last_rsi_low <- if (length(rsi_low_indices) > 0) max(rsi_low_indices) else 0
  last_rsi_high <- if (length(rsi_high_indices) > 0) max(rsi_high_indices) else 0

  if (last_rsi_low > 0 && last_rsi_high > 0) {
    if (last_rsi_low < last_rsi_high) {
      last_extreme <- "high"
    } else {
      last_extreme <- "low"
    }
  } else if (last_rsi_low > 0) {
    last_extreme <- "low"
  } else if (last_rsi_high > 0) {
    last_extreme <- "high"
  } else {
    last_extreme <- "unknown"
  }

  # Determine trading side based on trend + RSI
  if (is.na(current_rsi) || is.na(prev_rsi) || is.na(prev_rsi_2) || is.na(prev_rsi_3)) {
    side <- "hold"
  } else if (last_extreme == "low") {
    # Coming from oversold - looking for long entries
    if (trend == 1) {
      side <- "long"
    } else if (trend == -1 && current_rsi < prev_rsi &&
               (prev_rsi <= prev_rsi_2 || prev_rsi <= prev_rsi_3)) {
      side <- "neutral"
    } else if (trend == -1 && current_rsi >= prev_rsi &&
               (prev_rsi > prev_rsi_2 || prev_rsi >= prev_rsi_3)) {
      side <- "long"
    } else {
      side <- "hold"
    }
  } else if (last_extreme == "high") {
    # Coming from overbought - cautious on longs
    if (trend == -1) {
      side <- "neutral"
    } else if (trend == 1 && current_rsi < prev_rsi &&
               (prev_rsi <= prev_rsi_2 || prev_rsi <= prev_rsi_3)) {
      side <- "neutral"
    } else if (trend == 1 && current_rsi >= prev_rsi &&
               (prev_rsi > prev_rsi_2 || prev_rsi > prev_rsi_3)) {
      side <- "long"
    } else {
      side <- "hold"
    }
  } else {
    side <- "hold"
  }

  return(list(
    side = side,
    trend = trend,
    current_rsi = current_rsi,
    last_extreme = last_extreme,
    signal_strength = current_signal,
    trend_buy_threshold = trend_buy_threshold,
    trend_sell_threshold = trend_sell_threshold
  ))
}

# === Main Trading Loop ===
cat("=== EMA+RSI Multi-Pair Strategy Started ===\n")
cat(sprintf("Trading %d pairs\n", n_strategies))

while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(sprintf("\n[%s] Running strategy %d: %s\n",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), i, pairs[i]))

      # Get candles for this strategy
      candles <- get_strategy_candles(
        source = data_sources[i],
        pair = pairs[i],
        candles_pair = candles_pairs[i],
        days = 30,
        timeframe = timeframes[i],
        numcandles = 300
      )

      if (is.null(candles) || nrow(candles) == 0) {
        cat(sprintf("  ⚠️  No candle data for %s, skipping...\n", pairs[i]))
        next
      }

      # Validate candle data
      close_prices <- Cl(candles)
      if (length(close_prices) == 0 || all(is.na(close_prices))) {
        cat(sprintf("  ⚠️  Invalid candle data for %s (all NA), skipping...\n", pairs[i]))
        next
      }

      # Calculate signals
      result <- calculate_ema_rsi_signals(
        candles = candles,
        ema_fast_periods = ema_fast_list[[i]],
        ema_slow_periods = ema_slow_list[[i]],
        rsi_period = rsi_periods[i],
        rsi_low = rsi_lows[i],
        rsi_high = rsi_highs[i],
        trend_buy_mult = trend_buy_multipliers[i],
        trend_sell_mult = trend_sell_multipliers[i]
      )

      # Log signals
      cat(sprintf("  📊 Trend: %d | RSI: %.2f | Last Extreme: %s\n",
                  result$trend, result$current_rsi, result$last_extreme))
      cat(sprintf("  📈 Signal: %.4f (Buy: %.4f, Sell: %.4f)\n",
                  result$signal_strength, result$trend_buy_threshold, result$trend_sell_threshold))
      cat(sprintf("  🎯 Side: %s (was: %s)\n", result$side, last_sides[i]))

      # Update bot if side changed
      if (!identical(last_sides[i], result$side)) {
        cat(sprintf("  🔄 Side changed: %s → %s. Updating bot...\n",
                    last_sides[i], result$side))

        response <- itp_api(endpoint = "setBot", params = list(
          apiKey = apiKey,
          protocol = protocols[i],
          network = networks[i],
          pool = pools[i],
          pair = pairs[i],
          side = result$side,
          max_usd = max_usds[i],
          slippage = slippages[i],
          threshold = thresholds[i],
          share = shares[i],
          platform = platforms[i]
        ))

        last_sides[i] <- result$side

        # Send notification
        msg <- sprintf("🤖 %s Strategy Update\nPool: %s\nNetwork: %s\nSide: %s → %s\nTrend: %d | RSI: %.1f",
                      pairs[i], pools[i], networks[i], last_sides[i], result$side,
                      result$trend, result$current_rsi)
        discord(msg)

        cat("  ✅ Bot updated successfully\n")
      } else {
        cat("  ⏸️  Side unchanged, no update needed\n")
      }

    }, error = function(e) {
      error_msg <- sprintf("❌ Error in strategy %d (%s): %s", i, pairs[i], e$message)
      cat(paste0(error_msg, "\n"))
      discord(error_msg)
    })
  }

  cat(sprintf("\n⏰ Cycle complete. Sleeping 5 minutes...\n"))
  cat(sprintf("═══════════════════════════════════════════\n"))

  Sys.sleep(60 * 5)  # Sleep 5 minutes before next cycle
}
