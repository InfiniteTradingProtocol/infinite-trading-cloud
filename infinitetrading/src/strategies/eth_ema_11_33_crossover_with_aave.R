# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
source("~/infinitetrading/src/tradebot/aave_yield_optimizer.R")
library(TTR)
library(quantmod)

# === Strategy Configurations (Index-matched) ===
# NOTE: AAVE optimization behavior:
# - LONG signal: Only lends target asset if it's WETH or USDC
# - SELL/NEUTRAL signal: ALWAYS lends USDC to AAVE, regardless of what asset was sold
# This means ALL pairs (WETH, MORPHO, SNX, etc.) can earn yield on USDC during bearish periods
networks        = c("optimism","base","optimism")
protocols       = rep("dhedge",3)
pools           = c("0xb3daeb9b47bab1e56f29a77eb7a9c7f0ff63221d","0xa3ff483dcc9791d69d876981b1112269a6ed062d","0x86729853f9cca4c1ec0c160792f36e1bf97d58c3")
pairs           = c("WETH-USDC","MORPHO-USDC","SNX-USDC")  # All pairs earn yield on USDC side
candles_pairs   = c("ETH-USD","MORPHO-USD","SNX-USD")
timeframes      = c("6h","6h","6h")
slippages       = c(0.3,0.5,0.5)
shares          = c(100,100,100)
platforms       = c("odos","odos","odos")
max_usds        = c(10000,5000,5000)
thresholds      = c(1,1,1)
enable_aave     = c(TRUE, TRUE, TRUE)  # AAVE will auto-skip unsupported assets on LONG

# === Strategy Parameters ===
ema_fast = c(9,10,11,12,13)
ema_slow = c(29,30,31,32,33)

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)

# === Main Loop ===
cat("\n")
cat(rep("=", 80), "\n")
cat("Starting EMA Crossover Strategy with AAVE Yield Optimization\n")
cat(rep("=", 80), "\n")
cat("\n")

while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat("\n", rep("-", 80), "\n")
      cat(paste0("🔄 Running strategy ", i, "/", n_strategies, ": ", pairs[i], "\n"))
      cat(rep("-", 80), "\n\n")
      
      # Fetch candles
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles)
      
      # Calculate EMA crossover signals
      signal = 0
      n_strats = length(ema_fast) * length(ema_slow)
      
      for (j in 1:length(ema_fast)) {
        for (k in 1:length(ema_slow)) {
          EMA_FAST = EMA(close, n = ema_fast[j])
          EMA_SLOW = EMA(close, n = ema_slow[k])
          signal = signal + ifelse(last(EMA_FAST) > last(EMA_SLOW), 1, 0)
        }
      }
      
      # Calculate probability and determine side
      probability = signal / n_strats
      
      if (probability >= 0.30) { 
        side = "long" 
      } else if (probability > 0) { 
        side = "hold" 
      } else { 
        side = "neutral" 
      }
      
      cat(paste0("📊 Signal: ", signal, "/", n_strats, " (", round(probability * 100, 1), "%)\n"))
      cat(paste0("🎯 Direction: ", toupper(side), "\n\n"))
      
      # Check if signal changed
      if (last_sides[i] != side) {
        cat(paste0("🔔 Signal changed: ", last_sides[i], " → ", side, "\n\n"))
        last_sides[i] = side
        
        # Update bot configuration
        itp_api(endpoint = "setBot", params = list(
          apiKey = apiKey,
          protocol = protocols[i],
          network = networks[i],
          pool = pools[i],
          pair = pairs[i],
          side = side,
          max_usd = max_usds[i],
          slippage = slippages[i],
          threshold = thresholds[i],
          share = shares[i],
          platform = platforms[i]
        ))
        
        Sys.sleep(2)
        
        # Execute trade with AAVE optimization
        if (enable_aave[i]) {
          cat("💎 Executing with AAVE yield optimization...\n\n")
          execute_trade_with_aave_optimization(
            pool = pools[i],
            pair = pairs[i],
            side = side,
            network = networks[i],
            share = shares[i],
            slippage = slippages[i],
            platform = platforms[i],
            max_usd = max_usds[i],
            apiKey = apiKey,
            pool_composition = NULL,  # Will be fetched
            enable_aave = TRUE
          )
        } else {
          cat("📊 Executing standard trade (AAVE disabled)...\n\n")
          execute_standard_trade(
            pool = pools[i],
            pair = pairs[i],
            side = side,
            network = networks[i],
            share = shares[i],
            slippage = slippages[i],
            platform = platforms[i],
            max_usd = max_usds[i],
            apiKey = apiKey
          )
        }
        
        cat("\n✅ Strategy ", i, " execution completed\n")
      } else {
        cat(paste0("ℹ️ No signal change (still ", side, "), skipping execution\n"))
      }
      
    }, error = function(e) {
      cat(paste0("❌ Error in strategy ", i, ": ", e$message, "\n"))
      cat(paste0("Backtrace: ", paste(sys.calls(), collapse = "\n"), "\n"))
    })
  }
  
  cat("\n", rep("=", 80), "\n")
  cat("💤 Sleeping 15 minutes before next cycle...\n")
  cat(rep("=", 80), "\n\n")
  Sys.sleep(60 * 15)  # Sleep 15 mins before next cycle
}
