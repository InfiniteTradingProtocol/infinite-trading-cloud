#!/usr/bin/env Rscript

# Adaptive Strategy Backtest
# Combines EMA+RSI (for choppy markets) with EMA Crossover (for trending markets)
# Uses Coinbase API for real historical data

source("infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

cat("============================================================\n")
cat("ADAPTIVE STRATEGY BACKTEST\n")
cat("EMA+RSI (Choppy) + EMA Crossover (Trending)\n")
cat("============================================================\n\n")

# Fetch 4 years of 6h data from Coinbase (300 candles per batch)
cat("Fetching 4 years of ETH-USD 6h candles from Coinbase...\n")

all_candles <- list()
batch_size <- 300
target_candles <- 365.25 * 4 * 4  # 4 years * 4 candles per day = ~5844 candles
num_batches <- ceiling(target_candles / batch_size)

cat(sprintf("Target: %d candles in %d batches of 300\n\n", target_candles, num_batches))

current_end <- Sys.time()

for (i in 1:num_batches) {
  cat(sprintf("Batch %d/%d... ", i, num_batches))
  
  tryCatch({
    candles <- get_candles_with_retry(
      pair = "ETH-USD",
      numcandles = batch_size,
      timeframe = "6h"
    )
    
    if (!is.null(candles) && nrow(candles) > 0) {
      all_candles[[i]] <- candles
      cat(sprintf("✓ Got %d candles\n", nrow(candles)))
      
      # Move back in time for next batch
      oldest_time <- min(index(candles))
      current_end <- oldest_time - 6*3600  # Go back 6 hours from oldest
    } else {
      cat("✗ No data\n")
      break
    }
    
    Sys.sleep(1)  # Rate limiting
    
  }, error = function(e) {
    cat(sprintf("✗ Error: %s\n", e$message))
  })
  
  # Check if we have enough data
  total_candles <- sum(sapply(all_candles, nrow))
  if (total_candles >= target_candles) {
    cat(sprintf("\n✓ Reached target: %d candles\n", total_candles))
    break
  }
}

# Combine all batches
if (length(all_candles) == 0) {
  stop("Failed to fetch any data")
}

combined_candles <- do.call(rbind, rev(all_candles))
combined_candles <- combined_candles[!duplicated(index(combined_candles)), ]
combined_candles <- combined_candles[order(index(combined_candles)), ]

prices <- as.numeric(Cl(combined_candles))
n <- length(prices)

cat(sprintf("\n✓ Total: %d 6-hour candles (~%.1f years)\n", n, n/(365.25*4)))
cat(sprintf("Date range: %s to %s\n", 
            format(index(combined_candles)[1], "%Y-%m-%d"),
            format(index(combined_candles)[n], "%Y-%m-%d")))
cat(sprintf("Price: $%.2f → $%.2f\n\n", prices[1], prices[n]))

# Calculate buy-and-hold
bh_return <- (prices[n] - prices[1]) / prices[1] * 100

cat("============================================================\n")
cat(sprintf("📊 Buy & Hold: %.2f%% ($%.0f → $%.0f)\n", bh_return, prices[1], prices[n]))
cat("============================================================\n\n")

# ============================================================
# MARKET REGIME DETECTION
# ============================================================

detect_market_regime <- function(prices, lookback = 100) {
  # Use ADX (Average Directional Index) to detect trending vs choppy
  # High ADX (>25) = strong trend
  # Low ADX (<20) = choppy/ranging
  
  n <- length(prices)
  regimes <- rep("unknown", n)
  
  # Simple volatility-based approach
  for (i in lookback:n) {
    window <- prices[(i-lookback+1):i]
    
    # Calculate price range
    price_range <- (max(window) - min(window)) / mean(window)
    
    # Calculate directional movement
    price_change <- (window[length(window)] - window[1]) / window[1]
    
    # Trending: consistent direction + wide range
    if (abs(price_change) > 0.15 && price_range > 0.20) {
      regimes[i] <- "trending"
    }
    # Choppy: small net change despite wide range
    else if (abs(price_change) < 0.10 && price_range > 0.15) {
      regimes[i] <- "choppy"
    }
    # Range-bound: small range, small change
    else {
      regimes[i] <- "ranging"
    }
  }
  
  return(regimes)
}

# ============================================================
# STRATEGY 1: EMA+RSI (for choppy/ranging markets)
# ============================================================

strategy_ema_rsi <- function(prices, ema_fast, ema_slow, rsi_period, rsi_low, rsi_high) {
  n <- length(prices)
  
  ema_f <- EMA(prices, n = ema_fast)
  ema_s <- EMA(prices, n = ema_slow)
  rsi <- RSI(prices, n = rsi_period)
  
  signals <- (ema_f - ema_s) / ema_f
  signals_clean <- na.omit(signals)
  
  median_sig <- median(signals_clean)
  sd_sig <- sd(signals_clean)
  
  trend_buy <- median_sig + sd_sig/3
  trend_sell <- median_sig - sd_sig/3
  
  position <- rep(0, n)
  
  start_idx <- max(ema_slow, rsi_period) + 1
  
  for (i in start_idx:n) {
    if (is.na(signals[i]) || is.na(rsi[i])) {
      position[i] <- if(i > 1) position[i-1] else 0
      next
    }
    
    trend <- if(signals[i] >= trend_buy) 1 else if(signals[i] <= trend_sell) -1 else 0
    
    rsi_lows <- which(!is.na(rsi[1:i]) & rsi[1:i] <= rsi_low)
    rsi_highs <- which(!is.na(rsi[1:i]) & rsi[1:i] >= rsi_high)
    
    last_low <- if(length(rsi_lows) > 0) max(rsi_lows) else 0
    last_high <- if(length(rsi_highs) > 0) max(rsi_highs) else 0
    
    last_extreme <- if(last_low > 0 && last_high > 0) {
      if(last_low < last_high) "high" else "low"
    } else if(last_low > 0) "low" else if(last_high > 0) "high" else "unknown"
    
    prev_pos <- if(i > 1) position[i-1] else 0
    
    if (last_extreme == "low" && trend == 1 && prev_pos == 0) {
      position[i] <- 1
    } else if (prev_pos == 1 && (trend == -1 || last_extreme == "high")) {
      position[i] <- 0
    } else {
      position[i] <- prev_pos
    }
  }
  
  return(position)
}

# ============================================================
# STRATEGY 2: EMA Crossover (for trending markets)
# ============================================================

strategy_ema_crossover <- function(prices, ema_fast, ema_slow) {
  n <- length(prices)
  
  ema_f <- EMA(prices, n = ema_fast)
  ema_s <- EMA(prices, n = ema_slow)
  
  position <- rep(0, n)
  
  start_idx <- ema_slow + 1
  
  for (i in start_idx:n) {
    if (is.na(ema_f[i]) || is.na(ema_s[i])) {
      position[i] <- if(i > 1) position[i-1] else 0
      next
    }
    
    # Long when fast EMA above slow EMA
    if (ema_f[i] > ema_s[i]) {
      position[i] <- 1
    } else {
      position[i] <- 0
    }
  }
  
  return(position)
}

# ============================================================
# ADAPTIVE STRATEGY: Switches based on market regime
# ============================================================

strategy_adaptive <- function(prices, regimes) {
  n <- length(prices)
  
  # Get signals from both strategies
  ema_rsi_pos <- strategy_ema_rsi(prices, 9, 21, 14, 30, 70)
  crossover_pos <- strategy_ema_crossover(prices, 9, 21)
  
  position <- rep(0, n)
  
  for (i in 1:n) {
    if (regimes[i] == "choppy" || regimes[i] == "ranging") {
      position[i] <- ema_rsi_pos[i]
    } else if (regimes[i] == "trending") {
      position[i] <- crossover_pos[i]
    } else {
      position[i] <- if(i > 1) position[i-1] else 0
    }
  }
  
  return(position)
}

# ============================================================
# BACKTEST ENGINE
# ============================================================

backtest <- function(prices, position, strategy_name) {
  n <- length(prices)
  equity <- 1.0
  equity_curve <- rep(1.0, n)
  peak <- 1.0
  max_dd <- 0
  
  trades <- 0
  wins <- 0
  losses <- 0
  total_gain <- 0
  total_loss <- 0
  entry_price <- 0
  
  for (i in 2:n) {
    if (position[i] != position[i-1]) {
      if (position[i] == 1) {
        # Enter long
        entry_price <- prices[i]
        trades <- trades + 1
      } else if (position[i-1] == 1) {
        # Exit long
        pnl_pct <- (prices[i] - entry_price) / entry_price
        equity <- equity * (1 + pnl_pct)
        
        if (pnl_pct > 0) {
          wins <- wins + 1
          total_gain <- total_gain + pnl_pct
        } else {
          losses <- losses + 1
          total_loss <- total_loss + abs(pnl_pct)
        }
      }
    }
    
    # Mark-to-market
    if (position[i] == 1 && entry_price > 0) {
      mtm_pnl <- (prices[i] - entry_price) / entry_price
      equity_curve[i] <- equity * (1 + mtm_pnl)
    } else {
      equity_curve[i] <- equity
    }
    
    # Track drawdown
    if (equity_curve[i] > peak) peak <- equity_curve[i]
    dd <- (peak - equity_curve[i]) / peak
    if (dd > max_dd) max_dd <- dd
  }
  
  # Close final position
  if (position[n] == 1 && entry_price > 0) {
    pnl_pct <- (prices[n] - entry_price) / entry_price
    equity <- equity * (1 + pnl_pct)
    if (pnl_pct > 0) {
      wins <- wins + 1
      total_gain <- total_gain + pnl_pct
    } else {
      losses <- losses + 1
      total_loss <- total_loss + abs(pnl_pct)
    }
  }
  
  completed <- wins + losses
  win_rate <- if(completed > 0) wins / completed * 100 else 0
  profit_factor <- if(total_loss > 0) total_gain / total_loss else 0
  total_return <- (equity - 1) * 100
  exposure <- sum(position == 1) / n * 100
  
  returns <- diff(equity_curve) / equity_curve[-n]
  sharpe <- if(sd(returns, na.rm=TRUE) > 0) mean(returns, na.rm=TRUE) / sd(returns, na.rm=TRUE) * sqrt(365.25*4) else 0
  
  return(list(
    name = strategy_name,
    total_return = total_return,
    trades = trades,
    wins = wins,
    losses = losses,
    win_rate = win_rate,
    profit_factor = profit_factor,
    max_drawdown = max_dd * 100,
    exposure = exposure,
    sharpe = sharpe,
    equity = equity
  ))
}

# ============================================================
# RUN BACKTESTS
# ============================================================

cat("Detecting market regimes...\n")
regimes <- detect_market_regime(prices, 100)

choppy_pct <- sum(regimes == "choppy") / n * 100
trending_pct <- sum(regimes == "trending") / n * 100
ranging_pct <- sum(regimes == "ranging") / n * 100

cat(sprintf("  Choppy: %.1f%% | Trending: %.1f%% | Ranging: %.1f%%\n\n", 
            choppy_pct, trending_pct, ranging_pct))

cat("============================================================\n")
cat("BACKTESTING STRATEGIES\n")
cat("============================================================\n\n")

# Strategy positions
pos_ema_rsi_fast <- strategy_ema_rsi(prices, 4, 12, 4, 35, 65)
pos_ema_rsi_proposed <- strategy_ema_rsi(prices, 9, 21, 14, 30, 70)
pos_crossover <- strategy_ema_crossover(prices, 9, 21)
pos_adaptive <- strategy_adaptive(prices, regimes)

# Run backtests
results <- list(
  backtest(prices, pos_ema_rsi_fast, "🔴 EMA+RSI Current (4/12 RSI-4)"),
  backtest(prices, pos_ema_rsi_proposed, "🟢 EMA+RSI Proposed (9/21 RSI-14)"),
  backtest(prices, pos_crossover, "🔵 EMA Crossover (9/21)"),
  backtest(prices, pos_adaptive, "⭐ ADAPTIVE (Auto-switches)")
)

# Print results
for (res in results) {
  cat(sprintf("%s\n", res$name))
  cat(paste(rep("-", 60), collapse=""), "\n")
  cat(sprintf("Total Return:     %.2f%% (Buy-Hold: %.2f%%)\n", res$total_return, bh_return))
  cat(sprintf("Trades:           %d (Wins: %d, Losses: %d)\n", res$trades, res$wins, res$losses))
  cat(sprintf("Win Rate:         %.1f%%\n", res$win_rate))
  cat(sprintf("Profit Factor:    %.2f\n", res$profit_factor))
  cat(sprintf("Max Drawdown:     %.2f%%\n", res$max_drawdown))
  cat(sprintf("Market Exposure:  %.1f%%\n", res$exposure))
  cat(sprintf("Sharpe Ratio:     %.2f\n", res$sharpe))
  
  outperformance <- res$total_return - bh_return
  symbol <- if(outperformance > 0) "✅" else "❌"
  cat(sprintf("\n%s vs Buy-Hold:    %+.2f%%\n\n", symbol, outperformance))
}

# Final comparison
cat("============================================================\n")
cat("WINNER ANALYSIS\n")
cat("============================================================\n\n")

best_return_idx <- which.max(sapply(results, function(x) x$total_return))
best_sharpe_idx <- which.max(sapply(results, function(x) x$sharpe))

cat(sprintf("🏆 Best Return:  %s (%.2f%%)\n", results[[best_return_idx]]$name, results[[best_return_idx]]$total_return))
cat(sprintf("📈 Best Sharpe:  %s (%.2f)\n", results[[best_sharpe_idx]]$name, results[[best_sharpe_idx]]$sharpe))
cat(sprintf("🎯 Buy & Hold:   %.2f%%\n\n", bh_return))

adaptive_res <- results[[4]]
crossover_res <- results[[3]]

if (adaptive_res$total_return > crossover_res$total_return &&
    adaptive_res$total_return > bh_return) {
  cat("✅ ADAPTIVE STRATEGY WINS!\n\n")
  cat("The adaptive approach beats both:\n")
  cat(sprintf("  • %.2f%% better than EMA Crossover\n", adaptive_res$total_return - crossover_res$total_return))
  cat(sprintf("  • %.2f%% better than Buy-Hold\n", adaptive_res$total_return - bh_return))
  cat(sprintf("  • Sharpe ratio: %.2f\n", adaptive_res$sharpe))
} else if (crossover_res$total_return > bh_return) {
  cat("🔵 EMA CROSSOVER WINS!\n\n")
  cat("Simple trend-following beats adaptive in this period.\n")
  cat("This suggests the market was mostly trending.\n")
} else {
  cat("📊 BUY & HOLD WINS!\n\n")
  cat("Strong directional market - active strategies underperformed.\n")
}

cat("\n")
