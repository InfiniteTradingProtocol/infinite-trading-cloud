#!/usr/bin/env Rscript

# ============================================================================
# BACKTEST: cbBTC & OP Probability Models vs Buy-and-Hold
# Compares different sell thresholds (10%, 40%) against simple buy-and-hold
# ============================================================================

cat("=== PROBABILITY MODEL BACKTEST ===\n")
cat("Comparing Strategy Performance vs Buy-and-Hold\n\n")

# Auto-install required packages
required_packages = c("quantmod", "TTR", "lubridate")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(paste0("Installing ", pkg, "...\n"))
    install.packages(pkg, repos="http://cran.rstudio.com/", quiet=TRUE)
  }
}

library(quantmod)
library(TTR)
library(lubridate)

# ============================================================================
# BACKTEST ENGINE
# ============================================================================

run_backtest <- function(symbol, start_date, end_date, 
                        buy_threshold = 0.50, 
                        sell_threshold = 0.40,
                        initial_capital = 10000,
                        trade_fee = 0.003) {  # 0.3% per trade
  
  cat(paste0("\n--- Backtesting ", symbol, " ---\n"))
  cat(paste0("Period: ", start_date, " to ", end_date, "\n"))
  cat(paste0("Buy Threshold: ", buy_threshold*100, "%\n"))
  cat(paste0("Sell Threshold: ", sell_threshold*100, "%\n\n"))
  
  # Download price data
  tryCatch({
    getSymbols(symbol, src = "yahoo", from = start_date, to = end_date, auto.assign = TRUE)
    data <- get(symbol)
  }, error = function(e) {
    cat(paste0("Error downloading data for ", symbol, ": ", e$message, "\n"))
    return(NULL)
  })
  
  if (is.null(data) || nrow(data) == 0) {
    cat("No data available\n")
    return(NULL)
  }
  
  # Convert to 6-hour candles (matching strategy timeframe)
  data_6h <- to.period(data, period = "hours", k = 6)
  
  # Calculate indicators
  close <- Cl(data_6h)
  open <- Op(data_6h)
  high <- Hi(data_6h)
  
  n_fast <- 11
  n_slow <- 33
  
  EMA_FAST <- EMA(close, n = n_fast)
  EMA_FAST1 <- EMA(close, n = n_fast - 1)
  EMA_FAST2 <- EMA(close, n = n_fast - 2)
  
  EMA_SLOW <- EMA(close, n = n_slow)
  EMA_SLOW1 <- EMA(close, n = n_slow - 1)
  EMA_SLOW2 <- EMA(close, n = n_slow - 2)
  
  EMA200 <- EMA(close, n = 200)
  EMA100 <- EMA(close, n = 100)
  EMA50 <- EMA(close, n = 50)
  
  # Calculate probability for each candle
  n <- nrow(data_6h)
  probability <- rep(NA, n)
  
  for (i in 200:n) {  # Start after 200 candles for EMA200
    # Get current values
    idx <- i
    
    # Calculate all 41 signals
    SIGNAL1 <- as.numeric((EMA_FAST[idx] - EMA_SLOW[idx]) > 0)
    SIGNAL2 <- as.numeric(i > 1 && (EMA_FAST[idx-1] - EMA_SLOW[idx-1]) > 0)
    
    SIGNAL3 <- as.numeric((EMA_FAST[idx] - EMA_SLOW1[idx]) > 0)
    SIGNAL4 <- as.numeric(i > 1 && (EMA_FAST[idx-1] - EMA_SLOW1[idx-1]) > 0)
    
    SIGNAL5 <- as.numeric((EMA_FAST[idx] - EMA_SLOW2[idx]) > 0)
    SIGNAL6 <- as.numeric(i > 1 && (EMA_FAST[idx-1] - EMA_SLOW2[idx-1]) > 0)
    
    SIGNAL7 <- as.numeric((EMA_FAST1[idx] - EMA_SLOW[idx]) > 0)
    SIGNAL8 <- as.numeric(i > 1 && (EMA_FAST1[idx-1] - EMA_SLOW[idx-1]) > 0)
    
    SIGNAL9 <- as.numeric((EMA_FAST1[idx] - EMA_SLOW1[idx]) > 0)
    SIGNAL10 <- as.numeric(i > 1 && (EMA_FAST1[idx-1] - EMA_SLOW1[idx-1]) > 0)
    
    SIGNAL11 <- as.numeric((EMA_FAST1[idx] - EMA_SLOW2[idx]) > 0)
    SIGNAL12 <- as.numeric(i > 1 && (EMA_FAST1[idx-1] - EMA_SLOW2[idx-1]) > 0)
    
    SIGNAL13 <- as.numeric((EMA_FAST2[idx] - EMA_SLOW[idx]) > 0)
    SIGNAL14 <- as.numeric(i > 1 && (EMA_FAST2[idx-1] - EMA_SLOW[idx-1]) > 0)
    
    SIGNAL15 <- as.numeric((EMA_FAST2[idx] - EMA_SLOW1[idx]) > 0)
    SIGNAL16 <- as.numeric(i > 1 && (EMA_FAST2[idx-1] - EMA_SLOW1[idx-1]) > 0)
    
    SIGNAL17 <- as.numeric((EMA_FAST2[idx] - EMA_SLOW2[idx]) > 0)
    SIGNAL18 <- as.numeric(i > 1 && (EMA_FAST2[idx-1] - EMA_SLOW2[idx-1]) > 0)
    
    SIGNAL19 <- as.numeric(close[idx] > open[idx])
    SIGNAL20 <- as.numeric(i > 1 && close[idx] > close[idx-1])
    SIGNAL21 <- as.numeric(close[idx] > high[idx])
    
    SIGNAL22 <- as.numeric(SIGNAL19 && i > 1 && close[idx-1] > open[idx-1])
    SIGNAL23 <- as.numeric(SIGNAL22 && i > 2 && close[idx-2] > open[idx-2])
    
    SIGNAL24 <- as.numeric(close[idx] > EMA_FAST[idx])
    SIGNAL25 <- as.numeric(close[idx] > EMA_FAST1[idx])
    SIGNAL26 <- as.numeric(close[idx] > EMA_FAST2[idx])
    
    SIGNAL27 <- as.numeric(close[idx] > EMA_SLOW[idx])
    SIGNAL28 <- as.numeric(close[idx] > EMA_SLOW1[idx])
    SIGNAL29 <- as.numeric(close[idx] > EMA_SLOW2[idx])
    
    SIGNAL30 <- as.numeric(i > 1 && close[idx-1] > EMA_SLOW[idx-1])
    SIGNAL31 <- as.numeric(i > 1 && close[idx-1] > EMA_SLOW1[idx-1])
    SIGNAL32 <- as.numeric(i > 1 && close[idx-1] > EMA_SLOW2[idx-1])
    
    SIGNAL33 <- as.numeric(SIGNAL27 && SIGNAL28 && SIGNAL29)
    SIGNAL34 <- as.numeric(SIGNAL30 && SIGNAL31 && SIGNAL32)
    SIGNAL35 <- as.numeric(SIGNAL33 && SIGNAL34)
    SIGNAL36 <- as.numeric(SIGNAL27 && SIGNAL30)
    SIGNAL37 <- as.numeric(SIGNAL24 && SIGNAL25 && SIGNAL26)
    
    SIGNAL38 <- as.numeric(close[idx] > EMA200[idx])
    SIGNAL39 <- as.numeric(close[idx] > EMA100[idx])
    SIGNAL40 <- as.numeric(close[idx] > EMA50[idx])
    SIGNAL41 <- as.numeric(SIGNAL38 && SIGNAL39 && SIGNAL40)
    
    # Calculate probability (0 to 1)
    probability[idx] <- (SIGNAL1 + SIGNAL2 + SIGNAL3 + SIGNAL4 + SIGNAL5 + SIGNAL6 + 
                        SIGNAL7 + SIGNAL8 + SIGNAL9 + SIGNAL10 + SIGNAL11 + SIGNAL12 + 
                        SIGNAL13 + SIGNAL14 + SIGNAL15 + SIGNAL16 + SIGNAL17 + SIGNAL18 + 
                        SIGNAL19 + SIGNAL20 + SIGNAL21 + SIGNAL22 + SIGNAL23 + SIGNAL24 + 
                        SIGNAL25 + SIGNAL26 + SIGNAL27 + SIGNAL28 + SIGNAL29 + SIGNAL30 + 
                        SIGNAL31 + SIGNAL32 + SIGNAL33 + SIGNAL34 + SIGNAL35 + SIGNAL36 + 
                        SIGNAL37 + SIGNAL38 + SIGNAL39 + SIGNAL40 + SIGNAL41) / 41
  }
  
  # Simulate trading
  position <- "neutral"  # Start with no position (all USDC)
  cash <- initial_capital
  crypto_amount <- 0
  trades <- 0
  
  equity_curve <- rep(NA, n)
  
  for (i in 200:n) {
    prob <- probability[i]
    price <- as.numeric(close[i])
    
    if (is.na(prob) || is.na(price)) next
    
    # Trading logic
    if (position == "neutral" && prob >= buy_threshold) {
      # BUY: Convert all cash to crypto
      crypto_amount <- (cash * (1 - trade_fee)) / price
      cash <- 0
      position <- "long"
      trades <- trades + 1
    } else if (position == "long" && prob < sell_threshold) {
      # SELL: Convert all crypto to cash
      cash <- crypto_amount * price * (1 - trade_fee)
      crypto_amount <- 0
      position <- "neutral"
      trades <- trades + 1
    }
    
    # Calculate equity
    if (position == "long") {
      equity_curve[i] <- crypto_amount * price
    } else {
      equity_curve[i] <- cash
    }
  }
  
  # Calculate buy-and-hold performance
  buy_hold_start <- as.numeric(close[200])
  buy_hold_end <- as.numeric(close[n])
  buy_hold_return <- ((buy_hold_end / buy_hold_start) - 1) * 100
  buy_hold_final <- initial_capital * (buy_hold_end / buy_hold_start)
  
  # Calculate strategy performance
  strategy_final <- equity_curve[n]
  strategy_return <- ((strategy_final / initial_capital) - 1) * 100
  
  # Calculate max drawdown
  valid_equity <- equity_curve[!is.na(equity_curve)]
  if (length(valid_equity) > 0) {
    peak <- cummax(valid_equity)
    drawdown <- (valid_equity - peak) / peak * 100
    max_drawdown <- min(drawdown, na.rm = TRUE)
  } else {
    max_drawdown <- 0
  }
  
  # Handle NA values
  if (is.na(strategy_final)) {
    strategy_final <- cash + crypto_amount * as.numeric(close[n])
  }
  if (is.na(strategy_return)) {
    strategy_return <- ((strategy_final / initial_capital) - 1) * 100
  }
  
  # Results
  results <- list(
    symbol = symbol,
    start_price = buy_hold_start,
    end_price = buy_hold_end,
    initial_capital = initial_capital,
    buy_hold_final = buy_hold_final,
    buy_hold_return = buy_hold_return,
    strategy_final = strategy_final,
    strategy_return = strategy_return,
    trades = trades,
    max_drawdown = max_drawdown,
    outperformance = strategy_return - buy_hold_return,
    equity_curve = equity_curve,
    dates = index(data_6h)
  )
  
  return(results)
}

# ============================================================================
# PRINT RESULTS
# ============================================================================

print_results <- function(results) {
  if (is.null(results)) return(NULL)
  
  cat("\n╔════════════════════════════════════════════════════════╗\n")
  cat(paste0("║  ", results$symbol, " BACKTEST RESULTS\n"))
  cat("╠════════════════════════════════════════════════════════╣\n")
  cat(sprintf("║  Initial Capital:        $%.2f\n", results$initial_capital))
  cat(sprintf("║  Start Price:            $%.2f\n", results$start_price))
  cat(sprintf("║  End Price:              $%.2f\n", results$end_price))
  cat("║\n")
  cat("║  BUY-AND-HOLD STRATEGY:\n")
  cat(sprintf("║    Final Value:          $%.2f\n", results$buy_hold_final))
  cat(sprintf("║    Return:               %+.2f%%\n", results$buy_hold_return))
  cat("║\n")
  cat("║  PROBABILITY MODEL STRATEGY:\n")
  cat(sprintf("║    Final Value:          $%.2f\n", results$strategy_final))
  cat(sprintf("║    Return:               %+.2f%%\n", results$strategy_return))
  cat(sprintf("║    Number of Trades:     %d\n", results$trades))
  cat(sprintf("║    Max Drawdown:         %.2f%%\n", results$max_drawdown))
  cat("║\n")
  
  if (!is.na(results$outperformance) && results$outperformance > 0) {
    cat(sprintf("║  ✅ OUTPERFORMANCE:      +%.2f%%\n", results$outperformance))
    cat(sprintf("║  Strategy beats buy-and-hold by $%.2f\n", 
                results$strategy_final - results$buy_hold_final))
  } else if (!is.na(results$outperformance)) {
    cat(sprintf("║  ❌ UNDERPERFORMANCE:    %.2f%%\n", results$outperformance))
    cat(sprintf("║  Strategy loses to buy-and-hold by $%.2f\n", 
                results$buy_hold_final - results$strategy_final))
  } else {
    cat("║  ⚠️  Unable to calculate performance\n")
  }
  cat("╚════════════════════════════════════════════════════════╝\n")
}

# ============================================================================
# RUN BACKTESTS
# ============================================================================

# Set backtest period (1 year)
end_date <- Sys.Date()
start_date <- end_date - 365

cat("\n=== TESTING DIFFERENT THRESHOLDS ===\n")
cat("This will compare:\n")
cat("1. Old strategy (10% sell threshold)\n")
cat("2. New strategy (40% sell threshold)\n")
cat("3. Buy-and-hold\n\n")

# BTC Backtest
cat("\n", paste(rep("=", 60), collapse=""), "\n")
cat("BTC-USD BACKTESTS\n")
cat(paste(rep("=", 60), collapse=""), "\n")

btc_old <- run_backtest("BTC-USD", start_date, end_date, 
                        buy_threshold = 0.50, sell_threshold = 0.10,
                        initial_capital = 10000)
if (!is.null(btc_old)) {
  cat("\n--- OLD STRATEGY (10% sell threshold) ---")
  print_results(btc_old)
}

btc_new <- run_backtest("BTC-USD", start_date, end_date, 
                        buy_threshold = 0.50, sell_threshold = 0.40,
                        initial_capital = 10000)
if (!is.null(btc_new)) {
  cat("\n--- NEW STRATEGY (40% sell threshold) ---")
  print_results(btc_new)
}

# OP Backtest
cat("\n\n", paste(rep("=", 60), collapse=""), "\n")
cat("OP-USD BACKTESTS\n")
cat(paste(rep("=", 60), collapse=""), "\n")

# Try different OP symbols
op_symbols <- c("OP-USD", "OPUSD")
op_old <- NULL
op_new <- NULL

for (sym in op_symbols) {
  op_old <- run_backtest(sym, start_date, end_date, 
                         buy_threshold = 0.50, sell_threshold = 0.10,
                         initial_capital = 10000)
  if (!is.null(op_old)) {
    cat("\n--- OLD STRATEGY (10% sell threshold) ---")
    print_results(op_old)
    break
  }
}

for (sym in op_symbols) {
  op_new <- run_backtest(sym, start_date, end_date, 
                         buy_threshold = 0.50, sell_threshold = 0.40,
                         initial_capital = 10000)
  if (!is.null(op_new)) {
    cat("\n--- NEW STRATEGY (40% sell threshold) ---")
    print_results(op_new)
    break
  }
}

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n\n")
cat("╔════════════════════════════════════════════════════════════╗\n")
cat("║                    BACKTEST SUMMARY                        ║\n")
cat("╠════════════════════════════════════════════════════════════╣\n")

if (!is.null(btc_old) && !is.null(btc_new)) {
  cat("║  BTC Strategy Comparison:\n")
  cat(sprintf("║    Old (10%% threshold): %+.2f%% return\n", btc_old$strategy_return))
  cat(sprintf("║    New (40%% threshold): %+.2f%% return\n", btc_new$strategy_return))
  cat(sprintf("║    Buy-and-Hold:        %+.2f%% return\n", btc_old$buy_hold_return))
  improvement <- btc_new$strategy_return - btc_old$strategy_return
  if (improvement > 0) {
    cat(sprintf("║    ✅ 40%% threshold is %.2f%% better\n", improvement))
  } else {
    cat(sprintf("║    ❌ 40%% threshold is %.2f%% worse\n", improvement))
  }
  cat("║\n")
}

if (!is.null(op_old) && !is.null(op_new)) {
  cat("║  OP Strategy Comparison:\n")
  cat(sprintf("║    Old (10%% threshold): %+.2f%% return\n", op_old$strategy_return))
  cat(sprintf("║    New (40%% threshold): %+.2f%% return\n", op_new$strategy_return))
  cat(sprintf("║    Buy-and-Hold:        %+.2f%% return\n", op_old$buy_hold_return))
  improvement <- op_new$strategy_return - op_old$strategy_return
  if (improvement > 0) {
    cat(sprintf("║    ✅ 40%% threshold is %.2f%% better\n", improvement))
  } else {
    cat(sprintf("║    ❌ 40%% threshold is %.2f%% worse\n", improvement))
  }
}

cat("╚════════════════════════════════════════════════════════════╝\n")

cat("\n✅ Backtest complete!\n")
