#!/usr/bin/env Rscript

# Debug: Check actual probability values over time
library(quantmod)
library(TTR)

cat("=== PROBABILITY ANALYSIS ===\n\n")

# Download 2-year BTC data
end_date <- Sys.Date()
start_date <- end_date - 730

cat("Downloading BTC data...\n")
getSymbols("BTC-USD", src = "yahoo", from = start_date, to = end_date, auto.assign = TRUE)
data <- get("BTC-USD")
data_6h <- to.period(data, period = "hours", k = 6)

close <- Cl(data_6h)
n_fast <- 11
n_slow <- 33

EMA_FAST <- EMA(close, n = n_fast)
EMA_SLOW <- EMA(close, n = n_slow)
EMA200 <- EMA(close, n = 200)

# Calculate simplified probability for recent period
n <- nrow(data_6h)
recent_start <- max(1, n - 500)  # Last 500 6h candles (~125 days)

probabilities <- rep(NA, n)

for (i in 200:n) {
  # Simplified: just check a few key signals
  SIGNAL1 <- as.numeric((EMA_FAST[i] - EMA_SLOW[i]) > 0)
  SIGNAL2 <- as.numeric(close[i] > EMA_FAST[i])
  SIGNAL3 <- as.numeric(close[i] > EMA_SLOW[i])
  SIGNAL4 <- as.numeric(close[i] > EMA200[i])
  
  # Very simplified - just 4 signals
  probabilities[i] <- (SIGNAL1 + SIGNAL2 + SIGNAL3 + SIGNAL4) / 4
}

# Analyze recent probabilities
recent_probs <- probabilities[recent_start:n]
recent_probs <- recent_probs[!is.na(recent_probs)]

cat("\n=== PROBABILITY STATISTICS (Last 125 days) ===\n")
cat(sprintf("Min:      %.2f%%\n", min(recent_probs, na.rm=TRUE) * 100))
cat(sprintf("Max:      %.2f%%\n", max(recent_probs, na.rm=TRUE) * 100))
cat(sprintf("Mean:     %.2f%%\n", mean(recent_probs, na.rm=TRUE) * 100))
cat(sprintf("Median:   %.2f%%\n", median(recent_probs, na.rm=TRUE) * 100))
cat("\n")
cat(sprintf("Above 50%% (would buy):  %d periods (%.1f%%)\n", 
            sum(recent_probs > 0.50), sum(recent_probs > 0.50) / length(recent_probs) * 100))
cat(sprintf("Below 40%% (would sell): %d periods (%.1f%%)\n", 
            sum(recent_probs < 0.40), sum(recent_probs < 0.40) / length(recent_probs) * 100))
cat(sprintf("Below 10%% (old threshold): %d periods (%.1f%%)\n", 
            sum(recent_probs < 0.10), sum(recent_probs < 0.10) / length(recent_probs) * 100))

# Show recent values
cat("\n=== RECENT PROBABILITY VALUES (Last 20 periods) ===\n")
last_20_idx <- max(1, n-19):n
last_20_probs <- probabilities[last_20_idx]
last_20_dates <- index(data_6h)[last_20_idx]
last_20_prices <- as.numeric(close[last_20_idx])

for (i in 1:min(20, length(last_20_probs))) {
  if (!is.na(last_20_probs[i])) {
    signal <- if (last_20_probs[i] >= 0.50) "BUY ✅" else if (last_20_probs[i] < 0.40) "SELL ❌" else "HOLD ⏸️"
    cat(sprintf("%s  $%6.0f  Prob: %5.1f%%  %s\n", 
                format(last_20_dates[i], "%Y-%m-%d"), 
                last_20_prices[i],
                last_20_probs[i] * 100,
                signal))
  }
}

cat("\n=== ANALYSIS ===\n")
if (max(recent_probs, na.rm=TRUE) < 0.50) {
  cat("❌ PROBLEM: Probability NEVER reached 50% (buy threshold)\n")
  cat("   The strategy would make 0 trades - this is why backtests show 0 trades!\n")
  cat("   Possible reasons:\n")
  cat("   1. Market has been bearish (correct behavior)\n")
  cat("   2. Buy threshold (50%) is too high\n")
  cat("   3. Signal calculation is too conservative\n")
} else {
  cat("✅ Probability does reach 50%+ sometimes\n")
  cat(sprintf("   Would have made trades in %.1f%% of the time\n", 
              sum(recent_probs > 0.50) / length(recent_probs) * 100))
}

cat("\n")
