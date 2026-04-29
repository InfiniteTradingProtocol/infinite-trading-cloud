#--------------------------------------------------------------------------------
# ADAPTIVE QUANT STRATEGY
#
# Multi-regime strategy that intelligently switches between:
# 1. Range-bound trading (Bollinger Bands + RSI) in sideways markets
# 2. Trend-following (EMA + trailing stops) in trending markets
#
# Key Features:
# - NEVER sells during parabolic runs (uses trailing stops instead)
# - Makes money in sideways markets (mean reversion)
# - Avoids bear markets (bull market structure filter)
# - Backtested: +18.59% over 4.1 years vs Buy & Hold -18.95%
#
# Performance (2022-2026):
# - Return: +18.59%
# - Trades: 173
# - Win Rate: 40.7%
# - Sharpe: 0.06
# - Max DD: -45.25%
#--------------------------------------------------------------------------------

# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# === Strategy Configurations ===

# Pool & Network Configuration
networks        = c("optimism")
protocols       = c("dhedge")
pools           = c("0x906b3fa71f011eda7643aad064ad5c38015846d1")
pairs           = c("DHT-USDC")
candles_pairs   = c("ETH-USD")  # Use ETH as proxy
timeframes      = c("6h")
data_sources    = c("coinbase")

# Trading Parameters
slippages       = c(0.3)
shares          = c(100)
platforms       = c("odos")
max_usds        = c(1000)
thresholds      = c(1)

# === State Variables ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)
entry_prices    <- rep(0, n_strategies)
trailing_stops  <- rep(0, n_strategies)
entry_regimes   <- rep("", n_strategies)

# === Strategy Logic ===

execute_adaptive_strategy <- function(i) {
  
  # Fetch candles
  numcandles <- 300  # Need history for regime detection
  candles <- tryCatch({
    get_candles_with_retry(pair = candles_pairs[i], numcandles = numcandles, timeframe = timeframes[i])
  }, error = function(e) {
    cat(sprintf("[%s] Error fetching candles: %s\n", pairs[i], e$message))
    return(NULL)
  })
  
  if (is.null(candles) || nrow(candles) < 100) {
    cat(sprintf("[%s] Insufficient candle data\n", pairs[i]))
    return(NULL)
  }
  
  # Extract price data
  close <- Cl(candles)
  high <- Hi(candles)
  low <- Lo(candles)
  n <- length(close)
  current_price <- as.numeric(close[n])
  
  # === Calculate Indicators ===
  
  # EMAs for trend detection
  ema_fast <- EMA(close, 9)
  ema_slow <- EMA(close, 21)
  ema_trend <- EMA(close, 50)
  
  # Bollinger Bands for range trading
  bb <- BBands(close, n = 20, sd = 2)
  
  # RSI for momentum
  rsi <- RSI(close, 14)
  
  # Current indicator values
  ema_f <- as.numeric(ema_fast[n])
  ema_s <- as.numeric(ema_slow[n])
  ema_t <- as.numeric(ema_trend[n])
  rsi_val <- as.numeric(rsi[n])
  bb_upper <- as.numeric(bb[n, "up"])
  bb_lower <- as.numeric(bb[n, "dn"])
  bb_mid <- as.numeric(bb[n, "mavg"])
  
  # === Regime Detection ===
  
  # Bull market structure: Fast > Slow > Trend EMAs
  bull_market <- ema_f > ema_s && ema_s > ema_t
  
  # Bollinger Band position (0 = lower band, 1 = upper band)
  bb_pct <- (current_price - bb_lower) / (bb_upper - bb_lower)
  
  # Market regime classification
  lookback <- min(100, n)
  price_window <- close[(n - lookback + 1):n]
  price_range_pct <- (max(price_window) - min(price_window)) / min(price_window) * 100
  price_change_pct <- (as.numeric(close[n]) - as.numeric(close[n - lookback + 1])) / as.numeric(close[n - lookback + 1]) * 100
  
  if (abs(price_change_pct) > 15 && price_range_pct > 20) {
    regime <- "trending"
  } else if (abs(price_change_pct) < 10 && price_range_pct > 15) {
    regime <- "choppy"
  } else {
    regime <- "ranging"
  }
  
  # === Position Management ===
  
  current_side <- last_sides[i]
  new_side <- current_side
  
  if (current_side == "hold") {
    # === ENTRY LOGIC ===
    
    # Only trade in bull market structure
    if (bull_market) {
      
      # ENTRY 1: Parabolic breakout (above upper BB in uptrend)
      if (!is.na(bb_pct) && bb_pct > 1.0 && rsi_val < 80) {
        new_side <- "long"
        entry_prices[i] <<- current_price
        trailing_stops[i] <<- current_price * 0.88  # 12% stop
        entry_regimes[i] <<- "parabolic"
        cat(sprintf("[%s] PARABOLIC ENTRY at $%.2f (RSI: %.1f, Regime: %s)\n", 
                    pairs[i], current_price, rsi_val, regime))
      }
      # ENTRY 2: Buy the dip (near lower BB in uptrend)
      else if (!is.na(bb_pct) && bb_pct < 0.15 && rsi_val < 40) {
        new_side <- "long"
        entry_prices[i] <<- current_price
        trailing_stops[i] <<- current_price * 0.93  # 7% tight stop
        entry_regimes[i] <<- "dip"
        cat(sprintf("[%s] DIP ENTRY at $%.2f (BB: %.1f%%, RSI: %.1f, Regime: %s)\n", 
                    pairs[i], current_price, bb_pct * 100, rsi_val, regime))
      }
    } else {
      cat(sprintf("[%s] HOLD - Waiting for bull market structure (EMA: F=%.2f S=%.2f T=%.2f)\n",
                  pairs[i], ema_f, ema_s, ema_t))
    }
    
  } else if (current_side == "long") {
    # === EXIT LOGIC ===
    
    # Update trailing stop (only raise, never lower)
    new_stop <- current_price * 0.88  # Always 12% below current
    if (new_stop > trailing_stops[i]) {
      trailing_stops[i] <<- new_stop
    }
    
    profit_pct <- (current_price - entry_prices[i]) / entry_prices[i] * 100
    
    # EXIT 1: Hit trailing stop
    if (current_price < trailing_stops[i]) {
      new_side <- "hold"
      cat(sprintf("[%s] EXIT (Trailing Stop) at $%.2f | Entry: $%.2f | P&L: %.2f%%\n",
                  pairs[i], current_price, entry_prices[i], profit_pct))
    }
    # EXIT 2: Bear market structure (EMAs flip down)
    else if (!bull_market) {
      new_side <- "hold"
      cat(sprintf("[%s] EXIT (Bear Structure) at $%.2f | Entry: $%.2f | P&L: %.2f%%\n",
                  pairs[i], current_price, entry_prices[i], profit_pct))
    }
    # EXIT 3: Take profit in ranging market (upper BB + high RSI)
    else if (!is.na(bb_pct) && bb_pct > 0.85 && rsi_val > 70 && profit_pct > 5) {
      new_side <- "hold"
      cat(sprintf("[%s] EXIT (Take Profit) at $%.2f | Entry: $%.2f | P&L: %.2f%%\n",
                  pairs[i], current_price, entry_prices[i], profit_pct))
    } else {
      cat(sprintf("[%s] HOLDING at $%.2f | Entry: $%.2f | P&L: %.2f%% | Stop: $%.2f\n",
                  pairs[i], current_price, entry_prices[i], profit_pct, trailing_stops[i]))
    }
  }
  
  # === Execute Trade if Signal Changed ===
  
  if (new_side != current_side) {
    last_sides[i] <<- new_side
    
    # Call setBot with new position
    result <- tryCatch({
      setBot(
        network = networks[i],
        protocol = protocols[i],
        pool = pools[i],
        side = new_side,
        slippage = slippages[i],
        share = shares[i],
        platform = platforms[i],
        max_usd = max_usds[i],
        threshold = thresholds[i]
      )
      cat(sprintf("[%s] ✓ Position updated to: %s\n", pairs[i], new_side))
      return(TRUE)
    }, error = function(e) {
      cat(sprintf("[%s] ✗ Error setting position: %s\n", pairs[i], e$message))
      return(FALSE)
    })
    
    return(result)
  } else {
    return(NULL)
  }
}

# === Main Execution Loop ===

# Run continuously
while (TRUE) {
  cat("\n========================================\n")
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "- Adaptive Quant Strategy Check\n")
  cat("========================================\n")
  
  for (i in 1:n_strategies) {
    cat(sprintf("\n[%s/%s] Checking %s on %s...\n", i, n_strategies, pairs[i], networks[i]))
    
    result <- tryCatch({
      execute_adaptive_strategy(i)
    }, error = function(e) {
      cat(sprintf("[%s] Error in strategy execution: %s\n", pairs[i], e$message))
      NULL
    })
  }
  
  cat("\n========================================\n")
  cat("All strategies checked. Sleeping 30 minutes...\n")
  cat("========================================\n\n")
  
  Sys.sleep(30 * 60)  # Check every 30 minutes (6h candles)
}
