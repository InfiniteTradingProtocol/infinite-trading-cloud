#!/usr/bin/env Rscript

# EMA+RSI Strategy Backtest Comparison
# Tests current (4/12 RSI-4) vs proposed (9/21 RSI-14)

if (!require("httr", quietly = TRUE)) install.packages("httr", repos="http://cran.rstudio.com/")
if (!require("jsonlite", quietly = TRUE)) install.packages("jsonlite", repos="http://cran.rstudio.com/")
if (!require("TTR", quietly = TRUE)) install.packages("TTR", repos="http://cran.rstudio.com/")

library(httr)
library(jsonlite)
library(TTR)

# Fetch historical data from CoinGecko in batches
get_price_data <- function(coin_id = "ethereum", days_total = 1460) {
  cat(sprintf("Fetching %s data (%d days = ~4 years)...\n", coin_id, days_total))
  
  all_prices <- list()
  
  # CoinGecko max is ~365 days per request for hourly data
  # We'll fetch in batches
  max_days_per_batch <- 365
  num_batches <- ceiling(days_total / max_days_per_batch)
  
  for (batch in 1:num_batches) {
    days_to_fetch <- min(max_days_per_batch, days_total - (batch-1) * max_days_per_batch)
    
    cat(sprintf("  Batch %d/%d: Fetching %d days...\n", batch, num_batches, days_to_fetch))
    
    url <- paste0("https://api.coingecko.com/api/v3/coins/", coin_id, "/market_chart")
    response <- GET(url, query = list(vs_currency = "usd", days = days_to_fetch))
    
    if (status_code(response) != 200) {
      warning(sprintf("API error on batch %d: %d", batch, status_code(response)))
      next
    }
    
    data <- fromJSON(content(response, "text"))
    
    # Extract prices (timestamp, price)
    prices <- data$prices
    df <- data.frame(
      Time = as.POSIXct(prices[,1]/1000, origin = "1970-01-01", tz = "UTC"),
      Price = prices[,2]
    )
    
    all_prices[[batch]] <- df
    
    # Rate limiting
    if (batch < num_batches) {
      Sys.sleep(2)
    }
  }
  
  # Combine all batches
  combined <- do.call(rbind, all_prices)
  
  # Remove duplicates and sort
  combined <- combined[!duplicated(combined$Time), ]
  combined <- combined[order(combined$Time), ]
  
  cat(sprintf("  Got %d total data points\n", nrow(combined)))
  
  # Resample to 6-hour intervals (4 per day)
  combined$Hour6 <- floor(as.numeric(combined$Time) / (6*3600)) * (6*3600)
  combined$Time6h <- as.POSIXct(combined$Hour6, origin = "1970-01-01", tz = "UTC")
  
  # Take last price in each 6h window
  agg <- aggregate(Price ~ Time6h, data = combined, FUN = function(x) tail(x, 1))
  agg <- agg[order(agg$Time6h), ]
  
  cat(sprintf("  Resampled to %d 6-hour candles\n", nrow(agg)))
  
  return(agg$Price)
}

# Backtest a strategy
backtest_strategy <- function(prices, ema_fast, ema_slow, rsi_period, rsi_low, rsi_high) {
  n <- length(prices)
  
  # Calculate indicators
  ema_f <- EMA(prices, n = ema_fast)
  ema_s <- EMA(prices, n = ema_slow)
  rsi <- RSI(prices, n = rsi_period)
  
  # Normalized EMA signal
  signals <- (ema_f - ema_s) / ema_f
  signals_clean <- na.omit(signals)
  
  if (length(signals_clean) == 0) {
    return(list(
      total_return = 0, trades = 0, wins = 0, losses = 0, win_rate = 0,
      avg_gain = 0, avg_loss = 0, max_drawdown = 0, exposure = 0,
      sharpe = 0, profit_factor = 0
    ))
  }
  
  median_sig <- median(signals_clean)
  sd_sig <- sd(signals_clean)
  
  trend_buy_thresh <- median_sig + sd_sig/3
  trend_sell_thresh <- median_sig - sd_sig/3
  
  # Initialize tracking
  position <- 0
  entry_price <- 0
  equity <- 1.0
  equity_curve <- rep(1.0, n)
  peak_equity <- 1.0
  max_dd <- 0
  
  trades <- 0
  wins <- 0
  losses <- 0
  total_gain <- 0
  total_loss <- 0
  
  # Start after indicators are ready
  start_idx <- max(ema_slow, rsi_period) + 1
  
  for (i in start_idx:n) {
    if (is.na(signals[i]) || is.na(rsi[i])) {
      equity_curve[i] <- equity
      next
    }
    
    # Determine trend
    if (signals[i] >= trend_buy_thresh) {
      trend <- 1
    } else if (signals[i] <= trend_sell_thresh) {
      trend <- -1
    } else {
      trend <- 0
    }
    
    # Find last RSI extreme
    rsi_lows <- which(!is.na(rsi[1:i]) & rsi[1:i] <= rsi_low)
    rsi_highs <- which(!is.na(rsi[1:i]) & rsi[1:i] >= rsi_high)
    
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
    
    # Trading decisions
    new_position <- position
    
    # Entry signal: trend bullish + RSI oversold recovery
    if (position == 0 && last_extreme == "low" && trend == 1) {
      new_position <- 1
      entry_price <- prices[i]
      trades <- trades + 1
    }
    # Exit signal: trend bearish OR RSI overbought
    else if (position == 1 && (trend == -1 || (last_extreme == "high" && trend != 1))) {
      new_position <- 0
      
      # Calculate P&L
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
    
    # Update equity curve
    if (position == 1) {
      # Mark-to-market
      mtm_pnl <- (prices[i] - entry_price) / entry_price
      equity_curve[i] <- equity * (1 + mtm_pnl)
    } else {
      equity_curve[i] <- equity
    }
    
    # Track max drawdown
    if (equity_curve[i] > peak_equity) {
      peak_equity <- equity_curve[i]
    }
    dd <- (peak_equity - equity_curve[i]) / peak_equity
    if (dd > max_dd) {
      max_dd <- dd
    }
    
    position <- new_position
  }
  
  # Close final position if still open
  if (position == 1) {
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
  
  # Calculate metrics
  completed_trades <- wins + losses
  win_rate <- if(completed_trades > 0) wins / completed_trades * 100 else 0
  avg_gain <- if(wins > 0) total_gain / wins * 100 else 0
  avg_loss <- if(losses > 0) total_loss / losses * 100 else 0
  profit_factor <- if(total_loss > 0) total_gain / total_loss else 0
  
  total_return <- (equity - 1) * 100
  
  # Calculate Sharpe (simplified)
  returns <- diff(equity_curve) / equity_curve[-n]
  sharpe <- if(sd(returns, na.rm=TRUE) > 0) mean(returns, na.rm=TRUE) / sd(returns, na.rm=TRUE) * sqrt(252/4) else 0
  
  # Market exposure
  long_periods <- sum(diff(c(0, which(diff(c(0, position)) != 0), n)))
  exposure <- long_periods / (n - start_idx) * 100
  
  return(list(
    total_return = total_return,
    trades = trades,
    wins = wins,
    losses = losses,
    win_rate = win_rate,
    avg_gain = avg_gain,
    avg_loss = avg_loss,
    max_drawdown = max_dd * 100,
    exposure = exposure,
    sharpe = sharpe,
    profit_factor = profit_factor,
    final_equity = equity
  ))
}

# Main execution
cat(paste(rep("=", 60), collapse=""), "\n")
cat("EMA+RSI Strategy Backtest\n")
cat(paste(rep("=", 60), collapse=""), "\n\n")

# Fetch data (use ETH as proxy since DHT not available)
prices <- get_price_data("ethereum", 1460)  # 4 years
n <- length(prices)

cat(sprintf("Loaded %d 6-hour candles (~%.1f years)\n", n, n/(365.25*4)))
cat(sprintf("Date range: %s to %s\n", 
            format(Sys.time() - 60*60*6*n, "%Y-%m-%d"),
            format(Sys.time(), "%Y-%m-%d")))
cat(sprintf("Price range: $%.2f - $%.2f\n", min(prices), max(prices)))
cat(sprintf("Starting price: $%.2f\n", prices[1]))
cat(sprintf("Current price: $%.2f\n\n", tail(prices, 1)))

# Calculate buy-and-hold baseline
bh_return <- (prices[n] - prices[1]) / prices[1] * 100
bh_total_gain <- prices[n] - prices[1]

cat(sprintf("📊 Buy & Hold Performance:\n"))
cat(sprintf("   Total Return: %.2f%%\n", bh_return))
cat(sprintf("   Absolute Gain: $%.2f → $%.2f ($%.2f gain)\n", 
            prices[1], prices[n], bh_total_gain))
cat(sprintf("   Annualized: %.2f%%\n\n", bh_return / (n/(365.25*4))))

cat(paste(rep("=", 60), collapse=""), "\n")
cat("Testing Strategies...\n")
cat(paste(rep("=", 60), collapse=""), "\n\n")

# Test configurations
configs <- list(
  list(
    name = "🔴 CURRENT: 4/12 EMA, RSI-4",
    ema_fast = 4,
    ema_slow = 12,
    rsi_period = 4,
    rsi_low = 35,
    rsi_high = 65
  ),
  list(
    name = "🟢 PROPOSED: 9/21 EMA, RSI-14",
    ema_fast = 9,
    ema_slow = 21,
    rsi_period = 14,
    rsi_low = 30,
    rsi_high = 70
  ),
  list(
    name = "🔵 CONSERVATIVE: 12/26 EMA, RSI-14",
    ema_fast = 12,
    ema_slow = 26,
    rsi_period = 14,
    rsi_low = 30,
    rsi_high = 70
  ),
  list(
    name = "🟡 AGGRESSIVE: 6/18 EMA, RSI-14",
    ema_fast = 6,
    ema_slow = 18,
    rsi_period = 14,
    rsi_low = 35,
    rsi_high = 65
  )
)

results <- list()

for (cfg in configs) {
  cat(sprintf("\n%s\n", cfg$name))
  cat(rep("-", 60), "\n", sep="")
  
  result <- backtest_strategy(
    prices = prices,
    ema_fast = cfg$ema_fast,
    ema_slow = cfg$ema_slow,
    rsi_period = cfg$rsi_period,
    rsi_low = cfg$rsi_low,
    rsi_high = cfg$rsi_high
  )
  
  cat(sprintf("Total Return:     %.2f%% (Buy-Hold: %.2f%%)\n", result$total_return, bh_return))
  cat(sprintf("Trades:           %d (Wins: %d, Losses: %d)\n", result$trades, result$wins, result$losses))
  cat(sprintf("Win Rate:         %.1f%%\n", result$win_rate))
  cat(sprintf("Avg Win:          %.2f%%\n", result$avg_gain))
  cat(sprintf("Avg Loss:         %.2f%%\n", result$avg_loss))
  cat(sprintf("Profit Factor:    %.2f\n", result$profit_factor))
  cat(sprintf("Max Drawdown:     %.2f%%\n", result$max_drawdown))
  cat(sprintf("Market Exposure:  %.1f%%\n", result$exposure))
  cat(sprintf("Sharpe Ratio:     %.2f\n", result$sharpe))
  
  outperformance <- result$total_return - bh_return
  alpha_ratio <- if(bh_return != 0) result$total_return / bh_return else 0
  symbol <- if(outperformance > 0) "✅" else "❌"
  
  cat(sprintf("\n%s vs Buy-Hold:    %+.2f%% (%.2fx)\n", symbol, outperformance, alpha_ratio))
  
  results[[cfg$name]] <- result
}

# Find best strategy
cat("\n", paste(rep("=", 60), collapse=""), "\n")
cat("COMPARISON SUMMARY\n")
cat(paste(rep("=", 60), collapse=""), "\n\n")

best_return_idx <- which.max(sapply(results, function(x) x$total_return))
best_sharpe_idx <- which.max(sapply(results, function(x) x$sharpe))
best_winrate_idx <- which.max(sapply(results, function(x) x$win_rate))

cat(sprintf("🏆 Best Return:    %s (%.2f%%)\n", names(results)[best_return_idx], results[[best_return_idx]]$total_return))
cat(sprintf("📈 Best Sharpe:    %s (%.2f)\n", names(results)[best_sharpe_idx], results[[best_sharpe_idx]]$sharpe))
cat(sprintf("🎯 Best Win Rate:  %s (%.1f%%)\n", names(results)[best_winrate_idx], results[[best_winrate_idx]]$win_rate))

cat("\n", paste(rep("=", 60), collapse=""), "\n")
cat("KEY FINDINGS\n")
cat(paste(rep("=", 60), collapse=""), "\n\n")

current <- results[[1]]
proposed <- results[[2]]

improvement_return <- proposed$total_return - current$total_return
improvement_trades <- current$trades - proposed$trades
improvement_winrate <- proposed$win_rate - current$win_rate
improvement_sharpe <- proposed$sharpe - current$sharpe

cat("Switching from CURRENT (4/12 RSI-4) to PROPOSED (9/21 RSI-14):\n\n")
cat(sprintf("  Return:     %+.2f%% (%s)\n", improvement_return, 
            if(improvement_return > 0) "✅ BETTER" else "❌ WORSE"))
cat(sprintf("  Trades:     %+d (%s)\n", -improvement_trades,
            if(improvement_trades > 0) "✅ FEWER" else "❌ MORE"))
cat(sprintf("  Win Rate:   %+.1f%% (%s)\n", improvement_winrate,
            if(improvement_winrate > 0) "✅ BETTER" else "❌ WORSE"))
cat(sprintf("  Sharpe:     %+.2f (%s)\n", improvement_sharpe,
            if(improvement_sharpe > 0) "✅ BETTER" else "❌ WORSE"))
cat(sprintf("  Drawdown:   %.2f%% vs %.2f%% (%s)\n", 
            proposed$max_drawdown, current$max_drawdown,
            if(proposed$max_drawdown < current$max_drawdown) "✅ LESS RISK" else "❌ MORE RISK"))

cat("\n", paste(rep("=", 60), collapse=""), "\n")
cat("RECOMMENDATION\n")
cat(paste(rep("=", 60), collapse=""), "\n\n")

if (improvement_return > 0 && improvement_sharpe > 0) {
  cat("✅ STRONG RECOMMENDATION: Switch to PROPOSED (9/21 RSI-14)\n\n")
  cat("Benefits:\n")
  cat(sprintf("  • %.1f%% higher returns\n", improvement_return))
  cat(sprintf("  • %d fewer trades (%.1f%% reduction)\n", improvement_trades, improvement_trades/current$trades*100))
  cat(sprintf("  • Better risk-adjusted returns (Sharpe: %.2f vs %.2f)\n", proposed$sharpe, current$sharpe))
  cat(sprintf("  • Higher win rate (%.1f%% vs %.1f%%)\n", proposed$win_rate, current$win_rate))
} else if (improvement_sharpe > 0) {
  cat("✅ MODERATE RECOMMENDATION: Consider PROPOSED (9/21 RSI-14)\n\n")
  cat("Benefits:\n")
  cat(sprintf("  • Better risk-adjusted returns (Sharpe: %.2f vs %.2f)\n", proposed$sharpe, current$sharpe))
  cat(sprintf("  • Fewer trades = lower costs\n"))
} else {
  cat("⚠️  CURRENT strategy performed better in this backtest period\n")
  cat("   However, consider:\n")
  cat("   • Fast parameters may be overfitted to recent market\n")
  cat("   • Slower parameters more robust to regime changes\n")
  cat("   • Fewer trades = lower transaction costs in reality\n")
}

cat("\n")
