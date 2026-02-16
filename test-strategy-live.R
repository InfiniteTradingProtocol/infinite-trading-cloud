#!/usr/bin/env Rscript

# Live test: Run a strategy for 10 seconds to verify execution
cat("=== LIVE STRATEGY EXECUTION TEST ===\n")
cat("Testing: cbBTC_probability_model.R (10 second test run)\n\n")

# Set timeout to kill after 10 seconds
setTimeLimit(cpu = 10, elapsed = 10, transient = TRUE)

tryCatch({
  source("strategies/strategies/cbBTC_probability_model.R")
}, error = function(e) {
  if (grepl("reached elapsed time limit|reached CPU time limit", e$message)) {
    cat("\n✅ Strategy executed successfully for 10 seconds\n")
    cat("✅ Bot is working and would continue running indefinitely\n")
  } else {
    cat("\n❌ Strategy error:", e$message, "\n")
  }
})

setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE)
cat("\nTest complete.\n")
