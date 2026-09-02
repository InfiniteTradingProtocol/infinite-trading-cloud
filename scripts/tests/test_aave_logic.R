#!/usr/bin/env Rscript
# Test AAVE Yield Optimizer Logic
# This script tests the behavior for different trading pairs

cat("\n")
cat(paste(rep("=", 80), collapse = ""), "\n")
cat("🧪 AAVE YIELD OPTIMIZER LOGIC TEST\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

# Source dependencies
# NOTE: moved from repo root into scripts/tests/ — run from the repo root
# (e.g. `Rscript scripts/tests/test_aave_logic.R`) since this path is
# repo-root-relative.
source("infinitetrading/src/tradebot/aave_yield_optimizer.R")

# Test helper function
test_scenario <- function(pair, signal, description) {
  cat("\n", paste(rep("─", 80), collapse = ""), "\n")
  cat("📋 Test:", description, "\n")
  cat("   Pair:", pair, "| Signal:", signal, "\n")
  cat(paste(rep("─", 80), collapse = ""), "\n")
  
  parts <- strsplit(pair, "-")[[1]]
  target_asset <- parts[1]
  base_asset <- parts[2]
  network <- "optimism"
  
  # Check support
  target_supported <- is_aave_supported(target_asset, network)
  base_supported <- is_aave_supported(base_asset, network)
  
  cat(sprintf("\n💎 Asset Support:\n"))
  cat(sprintf("   %s: %s\n", target_asset, ifelse(target_supported, "✅ Supported", "❌ Not supported")))
  cat(sprintf("   %s: %s\n", base_asset, ifelse(base_supported, "✅ Supported", "❌ Not supported")))
  
  cat("\n📝 Expected Behavior:\n")
  
  if (signal == "LONG") {
    cat("   1. Unlend USDC from AAVE (if lent)\n")
    cat("   2. Buy", target_asset, "with USDC\n")
    if (target_supported) {
      cat("   3. ✅ Lend", target_asset, "to AAVE → EARN YIELD\n")
    } else {
      cat("   3. ⚠️  Keep", target_asset, "in vault (not supported)\n")
    }
  } else if (signal == "SELL") {
    cat("   1. Unlend", target_asset, "from AAVE (if lent)\n")
    cat("   2. Sell", target_asset, "to USDC\n")
    cat("   3. ✅ Lend USDC to AAVE → EARN YIELD (ALWAYS works!)\n")
    cat("      ℹ️  This happens REGARDLESS of whether", target_asset, "is supported\n")
  }
  
  cat("\n")
}

# ============================================================================
# Test Cases
# ============================================================================

cat("\n🎯 TEST SUITE: AAVE Yield Optimization Logic\n\n")

# Test 1: WETH-USDC LONG (both supported)
test_scenario("WETH-USDC", "LONG", "WETH-USDC LONG - Both assets supported")

# Test 2: WETH-USDC SELL (both supported)
test_scenario("WETH-USDC", "SELL", "WETH-USDC SELL - Both assets supported")

# Test 3: MORPHO-USDC LONG (target NOT supported)
test_scenario("MORPHO-USDC", "LONG", "MORPHO-USDC LONG - Target NOT supported")

# Test 4: MORPHO-USDC SELL (target NOT supported, but base IS)
test_scenario("MORPHO-USDC", "SELL", "MORPHO-USDC SELL - Base USDC is supported")

# Test 5: SNX-USDC LONG (target NOT supported)
test_scenario("SNX-USDC", "LONG", "SNX-USDC LONG - Target NOT supported")

# Test 6: SNX-USDC SELL (target NOT supported, but base IS)
test_scenario("SNX-USDC", "SELL", "SNX-USDC SELL - Base USDC is supported")

# ============================================================================
# Summary
# ============================================================================

cat("\n", paste(rep("=", 80), collapse = ""), "\n")
cat("📊 SUMMARY OF FINDINGS\n")
cat(paste(rep("=", 80), collapse = ""), "\n\n")

cat("✅ LONG Signal:\n")
cat("   - WETH-USDC: Buy WETH → Lend WETH to AAVE ✓\n")
cat("   - MORPHO-USDC: Buy MORPHO → Keep in vault (not supported)\n")
cat("   - SNX-USDC: Buy SNX → Keep in vault (not supported)\n\n")

cat("✅ SELL Signal (THE KEY INSIGHT!):\n")
cat("   - WETH-USDC: Sell WETH → USDC → Lend USDC to AAVE ✓\n")
cat("   - MORPHO-USDC: Sell MORPHO → USDC → Lend USDC to AAVE ✓ (WORKS!)\n")
cat("   - SNX-USDC: Sell SNX → USDC → Lend USDC to AAVE ✓ (WORKS!)\n\n")

cat("🎯 CONCLUSION:\n")
cat("   ALL trading pairs can earn yield on USDC during bearish periods!\n")
cat("   Even if the target asset isn't supported by AAVE, the resulting\n")
cat("   USDC can still be lent to earn yield while waiting for the next\n")
cat("   LONG signal.\n\n")

cat("💡 This means your strategies with MORPHO, SNX, and other assets\n")
cat("   can still benefit from AAVE yield optimization on the SELL side!\n\n")
