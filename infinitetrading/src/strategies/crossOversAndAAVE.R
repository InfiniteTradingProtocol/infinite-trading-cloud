# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
source("~/infinitetrading/src/tradebot/aave_yield_optimizer.R")
library(TTR)
library(quantmod)

# Load vault addresses (will be created by create_aave_vaults.R script)
vault_file <- "~/infinitetrading/src/strategies/aave_vault_addresses.R"
if (file.exists(vault_file)) {
  source(vault_file)
  cat("✓ Loaded AAVE vault addresses\n")
} else {
  stop("ERROR: Run scripts/create_aave_vaults.R first to create vaults!")
}

# === Strategy Configurations (Index-matched) ===
# NOTE: AAVE optimization behavior:
# - LONG signal: Only lends target asset if it's WETH or USDC
# - SELL/NEUTRAL signal: ALWAYS lends USDC to AAVE, regardless of what asset was sold
# This means ALL pairs can earn yield on USDC during bearish periods

networks        = c("base","optimism","base","optimism","base","optimism")
protocols       = rep("dhedge",6)
pools           = c(
  AAVE_VAULT_ADDRESSES[["MORPHO-USDC"]],
  AAVE_VAULT_ADDRESSES[["SNX-USDC"]],
  AAVE_VAULT_ADDRESSES[["AERO-USDC"]],
  AAVE_VAULT_ADDRESSES[["AAVE-USDC"]],
  AAVE_VAULT_ADDRESSES[["cbBTC-USDC"]],
  AAVE_VAULT_ADDRESSES[["WETH-USDC"]]
)
pairs           = c("MORPHO-USDC","SNX-USDC","AERO-USDC","AAVE-USDC","cbBTC-USDC","WETH-USDC")
candles_pairs   = c("MORPHO-USD","SNX-USD","AERO-USD","AAVE-USD","BTC-USD","ETH-USD")
timeframes      = c("6h","6h","6h","6h","6h","6h")
slippages       = c(0.5,0.5,0.5,0.5,0.3,0.3)
shares          = c(100,100,100,100,100,100)
platforms       = c("odos","odos","odos","odos","odos","odos")
max_usds        = c(5000,5000,5000,5000,10000,10000)
thresholds      = c(1,1,1,1,1,1)
enable_aave     = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE)  # AAVE enabled for all

# === Strategy Parameters ===
ema_fast = c(9,10,11,12,13)
ema_slow = c(29,30,31,32,33)

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)

# === Main Loop ===
cat("\n", paste(rep("=", 80), collapse = ""), "\n")
cat("STARTING CROSSOVERS + AAVE YIELD OPTIMIZATION\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("Strategies:\n")
for (i in 1:n_strategies) {
  cat(sprintf("  [%d] %s on %s: %s\n", i, pairs[i], networks[i], pools[i]))
}
cat("\n")

while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste(rep("-", 80), collapse = ""), "\n")
      cat(sprintf("[%d/%d] %s Strategy on %s\n", i, n_strategies, pairs[i], networks[i]))
      cat(paste(rep("-", 80), collapse = ""), "\n")
      
      # Get candles
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles)
      
      # Calculate EMA crossover signal
      signal = 0
      n_strats = length(ema_fast) * length(ema_slow)
      
      for (j in 1:length(ema_fast)) {
        for (k in 1:length(ema_slow)) {
          EMA_FAST = EMA(close, n = ema_fast[j])
          EMA_SLOW = EMA(close, n = ema_slow[k])
          signal = signal + ifelse(last(EMA_FAST) > last(EMA_SLOW), 1, 0)
        }
      }
      
      probability = signal / n_strats
      
      # Determine side based on probability
      if (probability >= 0.30) { 
        side = "long" 
      } else if (probability > 0) { 
        side = "hold" 
      } else { 
        side = "neutral" 
      }
      
      cat(sprintf("Signal: %d/%d  Probability: %.2f%%  Side: %s\n", signal, n_strats, probability * 100, toupper(side)))
      
      # Check if signal changed
      if (last_sides[i] != side) {
        cat(sprintf("📊 Signal changed: %s → %s\n", last_sides[i], side))
        last_sides[i] <- side
        
        # Execute trade with AAVE optimization
        cat("\n🎯 Executing trade with AAVE yield optimization...\n\n")
        
        success <- execute_trade_with_aave_optimization(
          pool = pools[i],
          pair = pairs[i],
          side = side,
          network = networks[i],
          share = shares[i],
          slippage = slippages[i],
          platform = platforms[i],
          max_usd = max_usds[i],
          apiKey = apiKey,
          enable_aave = enable_aave[i]
        )
        
        if (success) {
          cat("\n✅ Trade + AAVE optimization completed successfully\n")
          
          # Also set bot via API (for handling deposits)
          cat("\n📡 Setting bot via API (for deposit handling)...\n")
          bot_result <- itp_api(
            endpoint = "setBot",
            params = list(
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
            )
          )
          
          if (bot_result$status == "success") {
            cat("✅ Bot set successfully - deposits will trigger trades\n")
          } else {
            cat(sprintf("⚠️  Bot set failed: %s\n", bot_result$msg))
          }
          
        } else {
          cat("\n❌ Trade + AAVE optimization failed\n")
        }
        
      } else {
        cat(sprintf("ℹ️  No signal change (still %s)\n", side))
      }
      
      cat("\n")
      
    }, error = function(e) {
      cat(sprintf("❌ Error in strategy %d (%s): %s\n\n", i, pairs[i], e$message))
    })
  }
  
  cat(paste(rep("=", 80), collapse = ""), "\n")
  cat(sprintf("💤 Sleeping 15 minutes (next cycle at %s)...\n", format(Sys.time() + 60*15, "%H:%M:%S")))
  cat(paste(rep("=", 80), collapse = ""), "\n\n")
  
  Sys.sleep(60 * 15)  # Sleep 15 mins before next cycle
}
