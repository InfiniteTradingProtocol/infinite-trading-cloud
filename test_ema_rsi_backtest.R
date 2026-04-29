# Backtest EMA+RSI Strategy
source("infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# Fetch ETH data as proxy (since DHT not on Coinbase)
cat("Fetching 300 6-hour candles for ETH...\n")
candles <- get_candles_with_retry(pair = "ETH-USD", numcandles = 300, timeframe = "6h")

if (is.null(candles) || nrow(candles) == 0) {
  stop("Failed to fetch candles")
}

close <- Cl(candles)
n <- length(close)

cat(sprintf("Got %d candles\n", n))
cat(sprintf("Price range: $%.2f - $%.2f\n", min(close, na.rm=TRUE), max(close, na.rm=TRUE)))

# Test different parameter combinations
test_configs <- list(
  list(name="Current (4/12)", fast=4, slow=12, rsi=4, rsi_low=35, rsi_high=65),
  list(name="Longer EMAs (9/21)", fast=9, slow=21, rsi=14, rsi_low=30, rsi_high=70),
  list(name="Medium (6/18)", fast=6, slow=18, rsi=14, rsi_low=35, rsi_high=65),
  list(name="Very Fast (3/9)", fast=3, slow=9, rsi=4, rsi_low=40, rsi_high=60)
)

results <- data.frame()

for (config in test_configs) {
  cat(sprintf("\n=== Testing: %s ===\n", config$name))
  
  # Calculate indicators
  ema_fast <- EMA(close, n = config$fast)
  ema_slow <- EMA(close, n = config$slow)
  rsi <- RSI(close, n = config$rsi)
  
  # Signal calculation
  signals <- (ema_fast - ema_slow) / ema_fast
  signals_clean <- na.omit(signals)
  
  median_sig <- median(signals_clean)
  sd_sig <- sd(signals_clean)
  
  trend_buy_thresh <- median_sig + sd_sig/3
  trend_sell_thresh <- median_sig - sd_sig/3
  
  # Generate trades
  position <- rep(0, n)
  trades <- 0
  wins <- 0
  losses <- 0
  
  for (i in config$slow:n) {
    if (is.na(signals[i]) || is.na(rsi[i])) next
    
    # Determine trend
    if (signals[i] >= trend_buy_thresh) {
      trend <- 1
    } else if (signals[i] <= trend_sell_thresh) {
      trend <- -1
    } else {
      trend <- 0
    }
    
    # Find last RSI extreme
    rsi_lows <- which(!is.na(rsi[1:i]) & rsi[1:i] <= config$rsi_low)
    rsi_highs <- which(!is.na(rsi[1:i]) & rsi[1:i] >= config$rsi_high)
    
    last_low <- if(length(rsi_lows) > 0) max(rsi_lows) else 0
    last_high <- if(length(rsi_highs) > 0) max(rsi_highs) else 0
    
    if (last_low > 0 && last_high > 0) {
      last_extreme <- if(last_low < last_high) "high" else "low"
    } else if (last_low > 0) {
      last_extreme <- "low"
    } else if (last_high > 0) {
      last_extreme <- "high"
    } else {
      last_extreme <- "unknown"
    }
    
    # Trading logic
    prev_pos <- if(i > 1) position[i-1] else 0
    
    if (last_extreme == "low" && trend == 1) {
      position[i] <- 1  # Long
    } else if (last_extreme == "high" && trend == -1) {
      position[i] <- 0  # Neutral
    } else if (trend == -1) {
      position[i] <- 0  # Neutral
    } else {
      position[i] <- prev_pos  # Hold
    }
    
    # Count trades
    if (i > 1 && position[i] != position[i-1]) {
      trades <- trades + 1
      
      # Calculate win/loss
      if (position[i] == 1 && i < n) {
        # Entered long, check exit
        exit_idx <- i + 1
        while(exit_idx <= n && position[exit_idx] == 1) exit_idx <- exit_idx + 1
        if (exit_idx <= n) {
          pnl <- (close[exit_idx] - close[i]) / close[i]
          if (pnl > 0) wins <- wins + 1 else losses <- losses + 1
        }
      }
    }
  }
  
  # Calculate metrics
  buy_hold_return <- (close[n] - close[config$slow]) / close[config$slow] * 100
  
  long_periods <- sum(position == 1)
  long_pct <- long_periods / (n - config$slow) * 100
  
  win_rate <- if(trades > 0) wins / trades * 100 else 0
  
  cat(sprintf("Trades: %d | Win Rate: %.1f%% | Long Time: %.1f%%\n", 
              trades, win_rate, long_pct))
  
  results <- rbind(results, data.frame(
    Config = config$name,
    Trades = trades,
    WinRate = round(win_rate, 1),
    LongTime = round(long_pct, 1),
    stringsAsFactors = FALSE
  ))
}

cat("\n=== RESULTS SUMMARY ===\n")
print(results)

cat("\n=== ANALYSIS ===\n")
cat("Current strategy (4/12 EMA) observations:\n")
cat("- Very fast EMAs (4/12) are more reactive but may generate more false signals\n")
cat("- RSI period of 4 is extremely sensitive to short-term moves\n")
cat("- 6h timeframe means these indicators update 4x per day\n\n")

cat("Recommendations:\n")
cat("1. Consider 9/21 EMAs for 6h timeframe (more stable trend detection)\n")
cat("2. Use RSI-14 instead of RSI-4 (standard, less noise)\n")
cat("3. Widen RSI thresholds (30/70 instead of 35/65) to catch better extremes\n")
cat("4. Add volume confirmation if available\n")
cat("5. Consider adding a trend filter (e.g., only trade if above 200-period MA)\n")
