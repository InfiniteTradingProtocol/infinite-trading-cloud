#!/usr/bin/env Rscript

# ============================================================================
# EXTENDED BACKTEST: Multiple Time Periods
# Tests 2-year, 3-year, and 5-year periods
# ============================================================================

cat("=== EXTENDED BACKTEST: MULTIPLE TIME PERIODS ===\n\n")

# Auto-install required packages
required_packages = c("quantmod", "TTR", "lubridate")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos="http://cran.rstudio.com/", quiet=TRUE)
  }
}

library(quantmod)
library(TTR)
library(lubridate)

source("backtest-probability-models.R")  # Reuse the functions

# ============================================================================
# TEST MULTIPLE PERIODS
# ============================================================================

end_date <- Sys.Date()

test_periods <- list(
  list(name = "2-Year", years = 2),
  list(name = "3-Year", years = 3),
  list(name = "5-Year", years = 5)
)

all_results <- list()

for (period in test_periods) {
  start_date <- end_date - (period$years * 365)
  
  cat("\n")
  cat(paste(rep("=", 70), collapse=""), "\n")
  cat(paste0("  ", period$name, " BACKTEST (", start_date, " to ", end_date, ")\n"))
  cat(paste(rep("=", 70), collapse=""), "\n\n")
  
  # BTC Tests
  cat("BTC-USD:\n")
  btc_old <- run_backtest("BTC-USD", start_date, end_date, 
                          buy_threshold = 0.50, sell_threshold = 0.10,
                          initial_capital = 10000)
  btc_new <- run_backtest("BTC-USD", start_date, end_date, 
                          buy_threshold = 0.50, sell_threshold = 0.40,
                          initial_capital = 10000)
  
  if (!is.null(btc_old) && !is.null(btc_new)) {
    cat(sprintf("\n  Old (10%%): %.2f%% return, %d trades\n", 
                btc_old$strategy_return, btc_old$trades))
    cat(sprintf("  New (40%%): %.2f%% return, %d trades\n", 
                btc_new$strategy_return, btc_new$trades))
    cat(sprintf("  Buy-Hold:  %.2f%% return\n", btc_old$buy_hold_return))
    cat(sprintf("  Difference: %.2f%% (40%% vs 10%%)\n", 
                btc_new$strategy_return - btc_old$strategy_return))
  }
  
  # OP Tests
  cat("\nOP-USD:\n")
  op_old <- run_backtest("OP-USD", start_date, end_date, 
                         buy_threshold = 0.50, sell_threshold = 0.10,
                         initial_capital = 10000)
  op_new <- run_backtest("OP-USD", start_date, end_date, 
                         buy_threshold = 0.50, sell_threshold = 0.40,
                         initial_capital = 10000)
  
  if (!is.null(op_old) && !is.null(op_new)) {
    cat(sprintf("\n  Old (10%%): %.2f%% return, %d trades\n", 
                op_old$strategy_return, op_old$trades))
    cat(sprintf("  New (40%%): %.2f%% return, %d trades\n", 
                op_new$strategy_return, op_new$trades))
    cat(sprintf("  Buy-Hold:  %.2f%% return\n", op_old$buy_hold_return))
    cat(sprintf("  Difference: %.2f%% (40%% vs 10%%)\n", 
                op_new$strategy_return - op_old$strategy_return))
  }
  
  # Store results
  all_results[[period$name]] <- list(
    btc_old = btc_old,
    btc_new = btc_new,
    op_old = op_old,
    op_new = op_new
  )
}

# ============================================================================
# COMPREHENSIVE SUMMARY
# ============================================================================

cat("\n\n")
cat(paste(rep("=", 70), collapse=""), "\n")
cat("                    COMPREHENSIVE SUMMARY\n")
cat(paste(rep("=", 70), collapse=""), "\n\n")

cat("╔════════════════════════════════════════════════════════════════════╗\n")
cat("║                        BTC-USD PERFORMANCE                         ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")
cat("║  Period  │  Buy-Hold  │  Old (10%)  │  New (40%)  │  Winner       ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")

for (period in test_periods) {
  results <- all_results[[period$name]]
  if (!is.null(results$btc_old) && !is.null(results$btc_new)) {
    bh <- results$btc_old$buy_hold_return
    old <- results$btc_old$strategy_return
    new <- results$btc_new$strategy_return
    
    winner <- if (new > old) "✅ 40%" else if (old > new) "❌ 10%" else "🟰 Tie"
    diff <- abs(new - old)
    
    cat(sprintf("║  %-7s│  %+7.2f%%  │  %+8.2f%%  │  %+8.2f%%  │  %-12s ║\n",
                period$name, bh, old, new, 
                paste0(winner, " (", sprintf("%.1f%%", diff), ")")))
  }
}

cat("╚════════════════════════════════════════════════════════════════════╝\n\n")

cat("╔════════════════════════════════════════════════════════════════════╗\n")
cat("║                         OP-USD PERFORMANCE                         ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")
cat("║  Period  │  Buy-Hold  │  Old (10%)  │  New (40%)  │  Winner       ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")

for (period in test_periods) {
  results <- all_results[[period$name]]
  if (!is.null(results$op_old) && !is.null(results$op_new)) {
    bh <- results$op_old$buy_hold_return
    old <- results$op_old$strategy_return
    new <- results$op_new$strategy_return
    
    winner <- if (new > old) "✅ 40%" else if (old > new) "❌ 10%" else "🟰 Tie"
    diff <- abs(new - old)
    
    cat(sprintf("║  %-7s│  %+7.2f%%  │  %+8.2f%%  │  %+8.2f%%  │  %-12s ║\n",
                period$name, bh, old, new, 
                paste0(winner, " (", sprintf("%.1f%%", diff), ")")))
  }
}

cat("╚════════════════════════════════════════════════════════════════════╝\n\n")

# Trade frequency analysis
cat("╔════════════════════════════════════════════════════════════════════╗\n")
cat("║                     TRADING ACTIVITY ANALYSIS                      ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")

for (period in test_periods) {
  results <- all_results[[period$name]]
  cat(sprintf("║  %s:\n", period$name))
  
  if (!is.null(results$btc_old)) {
    cat(sprintf("║    BTC - Old: %d trades, New: %d trades\n", 
                results$btc_old$trades, results$btc_new$trades))
  }
  if (!is.null(results$op_old)) {
    cat(sprintf("║    OP  - Old: %d trades, New: %d trades\n", 
                results$op_old$trades, results$op_new$trades))
  }
  cat("║\n")
}

cat("╚════════════════════════════════════════════════════════════════════╝\n\n")

# Final recommendation
cat("╔════════════════════════════════════════════════════════════════════╗\n")
cat("║                      FINAL RECOMMENDATION                          ║\n")
cat("╠════════════════════════════════════════════════════════════════════╣\n")

# Calculate average performance difference
btc_diffs <- c()
op_diffs <- c()

for (period in test_periods) {
  results <- all_results[[period$name]]
  if (!is.null(results$btc_old) && !is.null(results$btc_new)) {
    btc_diffs <- c(btc_diffs, results$btc_new$strategy_return - results$btc_old$strategy_return)
  }
  if (!is.null(results$op_old) && !is.null(results$op_new)) {
    op_diffs <- c(op_diffs, results$op_new$strategy_return - results$op_old$strategy_return)
  }
}

avg_btc_diff <- mean(btc_diffs, na.rm = TRUE)
avg_op_diff <- mean(op_diffs, na.rm = TRUE)
avg_overall <- mean(c(btc_diffs, op_diffs), na.rm = TRUE)

cat(sprintf("║  Average Performance Difference (40%% vs 10%%):\n"))
cat(sprintf("║    BTC:     %+.2f%%\n", avg_btc_diff))
cat(sprintf("║    OP:      %+.2f%%\n", avg_op_diff))
cat(sprintf("║    Overall: %+.2f%%\n", avg_overall))
cat("║\n")

if (avg_overall > 0) {
  cat("║  ✅ RECOMMENDATION: USE 40% THRESHOLD\n")
  cat(sprintf("║     Outperforms by average of %.2f%%\n", avg_overall))
} else if (avg_overall < 0) {
  cat("║  ⚠️  RECOMMENDATION: USE 10% THRESHOLD\n")
  cat(sprintf("║     Underperforms by average of %.2f%%\n", abs(avg_overall)))
} else {
  cat("║  🟰 RECOMMENDATION: EITHER THRESHOLD WORKS\n")
  cat("║     No significant difference in performance\n")
}

cat("╚════════════════════════════════════════════════════════════════════╝\n")

cat("\n✅ Extended backtest complete!\n")
cat("Results saved to: extended-backtest-results.txt\n")
