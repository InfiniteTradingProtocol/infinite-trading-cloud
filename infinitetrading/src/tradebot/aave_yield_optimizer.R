# ==============================================================================
# AAVE Yield Optimizer for Trading Strategies
# ==============================================================================
# This module handles automatic lending/unlending to AAVE v3 to maximize yield
# during idle periods while maintaining trading strategy execution.
#
# Core Logic:
# - LONG signal: If holding target asset → lend to AAVE
#                If USDC is lent → unlend, buy asset, lend asset
# - SELL signal: If asset is lent → unlend asset, sell to USDC, lend USDC
# ==============================================================================

# --- Configuration ---
AAVE_PLATFORM <- "aavev3"
AAVE_CONTRACTS <- list(
  optimism = "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  polygon  = "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  base     = "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
  arbitrum = "0x42EC99A020B78C449d17d93bC4c89e0189B5811d"
)

# Assets supported by AAVE v3 on each network
AAVE_SUPPORTED_ASSETS <- list(
  optimism = c("USDC", "WETH", "USDT", "WBTC", "LINK", "AAVE"),
  polygon  = c("USDC", "WETH", "USDT", "WBTC", "LINK", "AAVE", "WMATIC"),
  base     = c("USDC", "WETH", "cbETH"),
  arbitrum = c("USDC", "WETH", "USDT", "WBTC", "LINK", "AAVE")
)

# For your specific use case, whitelist only WETH and USDC
SAFE_AAVE_ASSETS <- c("USDC", "WETH")

# --- Helper Functions ---

#' Check if asset is supported by AAVE on the network
is_aave_supported <- function(asset, network) {
  # First check the safe whitelist (USDC, WETH only)
  if (!(asset %in% SAFE_AAVE_ASSETS)) {
    return(FALSE)
  }
  
  # Then check if it's available on the network
  supported <- AAVE_SUPPORTED_ASSETS[[tolower(network)]]
  if (is.null(supported)) {
    return(FALSE)
  }
  
  return(asset %in% supported)
}

#' Get AAVE contract address for network
get_aave_contract <- function(network) {
  contract <- AAVE_CONTRACTS[[tolower(network)]]
  if (is.null(contract)) {
    stop(paste("AAVE contract not configured for network:", network))
  }
  return(contract)
}

#' Check if asset is supplied to AAVE
#' @return list(is_supplied=TRUE/FALSE, amount=numeric)
check_aave_supplied <- function(pool, asset, network, apiKey) {
  tryCatch({
    result <- itp_api(
      endpoint = "aaveV3/getSupplied",
      params = list(
        pool = pool,
        network = network,
        asset = asset,
        protocol = "dhedge",
        apiKey = apiKey
      )
    )
    
    if (!is.null(result$data) && length(result$data) > 0) {
      amount <- as.numeric(result$data[1])
      return(list(is_supplied = amount > 0.01, amount = amount))
    }
    return(list(is_supplied = FALSE, amount = 0))
  }, error = function(e) {
    cat(paste0("⚠️ Error checking AAVE supply for ", asset, ": ", e$message, "\n"))
    return(list(is_supplied = FALSE, amount = 0))
  })
}

#' Approve asset for AAVE lending
approve_for_aave <- function(pool, asset, network, apiKey) {
  tryCatch({
    cat(paste0("🔓 Approving ", asset, " for AAVE lending...\n"))
    result <- itp_api(
      endpoint = "approve",
      params = list(
        pool = pool,
        network = network,
        asset = asset,
        platform = AAVE_PLATFORM,
        apiKey = apiKey
      )
    )
    
    if (!is.null(result$status) && result$status == "success") {
      cat(paste0("✅ ", asset, " approved for AAVE\n"))
      Sys.sleep(3) # Wait for approval to confirm
      return(TRUE)
    }
    cat(paste0("❌ Failed to approve ", asset, " for AAVE\n"))
    return(FALSE)
  }, error = function(e) {
    cat(paste0("⚠️ Error approving ", asset, ": ", e$message, "\n"))
    return(FALSE)
  })
}

#' Lend asset to AAVE
#' @param share Percentage of balance to lend (default 100)
lend_to_aave <- function(pool, asset, network, share = 100, apiKey) {
  # Check if asset is supported
  if (!is_aave_supported(asset, network)) {
    cat(paste0("ℹ️ ", asset, " not supported by AAVE on ", network, ", skipping lending\n"))
    return(FALSE)
  }
  
  tryCatch({
    cat(paste0("💰 Lending ", share, "% of ", asset, " to AAVE...\n"))
    
    # First approve if needed
    approve_for_aave(pool, asset, network, apiKey)
    
    # Then lend
    result <- itp_api(
      endpoint = "aaveV3/lend",
      params = list(
        pool = pool,
        network = network,
        asset = asset,
        share = share,
        apiKey = apiKey
      )
    )
    
    if (!is.null(result$status) && result$status == "success") {
      cat(paste0("✅ Successfully lent ", asset, " to AAVE. Tx: ", result$msg, "\n"))
      Sys.sleep(5) # Wait for transaction to confirm
      return(TRUE)
    }
    cat(paste0("❌ Failed to lend ", asset, " to AAVE\n"))
    return(FALSE)
  }, error = function(e) {
    cat(paste0("⚠️ Error lending ", asset, ": ", e$message, "\n"))
    return(FALSE)
  })
}

#' Unlend (withdraw) asset from AAVE
#' @param share Percentage of supplied balance to withdraw (default 100)
unlend_from_aave <- function(pool, asset, network, share = 100, apiKey) {
  # Check if asset is supported
  if (!is_aave_supported(asset, network)) {
    cat(paste0("ℹ️ ", asset, " not supported by AAVE on ", network, ", skipping unlending\n"))
    return(FALSE)
  }
  
  tryCatch({
    cat(paste0("🏦 Unlending ", share, "% of ", asset, " from AAVE...\n"))
    
    result <- itp_api(
      endpoint = "aaveV3/unlend",
      params = list(
        pool = pool,
        network = network,
        asset = asset,
        share = share,
        apiKey = apiKey
      )
    )
    
    if (!is.null(result$status) && result$status == "success") {
      cat(paste0("✅ Successfully unlent ", asset, " from AAVE. Tx: ", result$msg, "\n"))
      Sys.sleep(5) # Wait for transaction to confirm
      return(TRUE)
    }
    cat(paste0("❌ Failed to unlend ", asset, " from AAVE\n"))
    return(FALSE)
  }, error = function(e) {
    cat(paste0("⚠️ Error unlending ", asset, ": ", e$message, "\n"))
    return(FALSE)
  })
}

# ==============================================================================
# Main Optimization Function
# ==============================================================================

#' Execute trade with AAVE yield optimization
#' 
#' @param pool Pool address
#' @param pair Trading pair (e.g., "WETH-USDC")
#' @param side Trade signal: "long", "sell", "hold", "neutral"
#' @param network Network name
#' @param share Trading share percentage
#' @param slippage Trading slippage
#' @param platform Trading platform (default: "odos")
#' @param max_usd Maximum USD trade value
#' @param apiKey API key for authentication
#' @param pool_composition Current pool composition (optional, will fetch if NULL)
#' @param enable_aave Enable AAVE optimization (default: TRUE)
#'
#' @return TRUE if execution successful, FALSE otherwise
execute_trade_with_aave_optimization <- function(
  pool,
  pair,
  side,
  network,
  share = 100,
  slippage = 0.5,
  platform = "odos",
  max_usd = NULL,
  apiKey,
  pool_composition = NULL,
  enable_aave = TRUE
) {
  
  # Parse pair
  parts <- strsplit(pair, "-")[[1]]
  target_asset <- parts[1]  # e.g., WETH, WBTC, wstETH
  base_asset <- parts[2]    # e.g., USDC
  
  cat(paste0("\n", rep("=", 80), "\n"))
  cat(paste0("🎯 Executing trade with AAVE optimization\n"))
  cat(paste0("Pair: ", pair, " | Signal: ", side, " | Network: ", network, "\n"))
  cat(paste0(rep("=", 80), "\n\n"))
  
  # Fetch pool composition if not provided
  if (is.null(pool_composition)) {
    pool_composition <- pool_comp(pool = pool, network = network, protocol = "dhedge")
    if (is.null(pool_composition) || ncol(pool_composition) < 5) {
      cat("❌ Failed to fetch pool composition\n")
      return(FALSE)
    }
  }
  
  # Get current balances
  target_balance <- get_balance(pool_composition, target_asset, protocol = "dhedge")
  base_balance <- get_balance(pool_composition, base_asset, protocol = "dhedge")
  
  cat(paste0("📊 Current balances:\n"))
  cat(paste0("   ", target_asset, ": ", round(target_balance, 6), "\n"))
  cat(paste0("   ", base_asset, ": ", round(base_balance, 2), "\n\n"))
  
  if (!enable_aave) {
    cat("ℹ️ AAVE optimization disabled, executing standard trade\n\n")
    return(execute_standard_trade(pool, pair, side, network, share, slippage, platform, max_usd, apiKey))
  }
  
  # Check AAVE positions
  target_aave <- check_aave_supplied(pool, target_asset, network, apiKey)
  base_aave <- check_aave_supplied(pool, base_asset, network, apiKey)
  
  cat(paste0("🏦 AAVE positions:\n"))
  cat(paste0("   ", target_asset, " supplied: ", ifelse(target_aave$is_supplied, paste0(round(target_aave$amount, 6), " ✓"), "None"), "\n"))
  cat(paste0("   ", base_asset, " supplied: ", ifelse(base_aave$is_supplied, paste0(round(base_aave$amount, 2), " ✓"), "None"), "\n"))
  
  # Check if assets are supported by AAVE
  target_supported <- is_aave_supported(target_asset, network)
  base_supported <- is_aave_supported(base_asset, network)
  
  cat(paste0("💎 AAVE support:\n"))
  cat(paste0("   ", target_asset, ": ", ifelse(target_supported, "✅ Supported", "❌ Not supported (will skip lending)"), "\n"))
  cat(paste0("   ", base_asset, ": ", ifelse(base_supported, "✅ Supported", "❌ Not supported (will skip lending)"), "\n\n"))
  
  # ====================
  # LONG SIGNAL LOGIC
  # ====================
  if (side == "long" || side == "buy") {
    cat("📈 LONG signal detected\n\n")
    
    # Step 1: Check if we have USDC supplied to AAVE - need to unlend it first
    if (base_aave$is_supplied) {
      cat(paste0("Step 1: Unlending ", base_asset, " from AAVE to free capital for buying...\n"))
      if (!unlend_from_aave(pool, base_asset, network, 100, apiKey)) {
        cat("❌ Failed to unlend USDC, cannot proceed with trade\n")
        return(FALSE)
      }
      # Refresh composition after unlending
      pool_composition <- pool_comp(pool = pool, network = network, protocol = "dhedge")
      base_balance <- get_balance(pool_composition, base_asset, protocol = "dhedge")
    }
    
    # Step 2: If we need to buy target asset (don't have enough)
    if (target_balance < 0.001 && base_balance > 1) {
      cat(paste0("Step 2: Buying ", target_asset, " with ", base_asset, "...\n"))
      trade_result <- trade(
        protocol = "dhedge",
        ep = "api",
        from = base_asset,
        to = target_asset,
        platform = platform,
        network = network,
        share = share,
        slippage = slippage,
        pool = pool,
        max_usd = max_usd,
        apiKey = apiKey
      )
      
      if (is.null(trade_result) || trade_result == "fail") {
        cat("❌ Trade failed\n")
        return(FALSE)
      }
      
      Sys.sleep(5)
      # Refresh composition after trade
      pool_composition <- pool_comp(pool = pool, network = network, protocol = "dhedge")
      target_balance <- get_balance(pool_composition, target_asset, protocol = "dhedge")
    }
    
    # Step 3: If target asset is not yet in AAVE, lend it
    if (target_balance > 0.001 && !target_aave$is_supplied) {
      if (target_supported) {
        cat(paste0("Step 3: Lending ", target_asset, " to AAVE to earn yield...\n"))
        lend_to_aave(pool, target_asset, network, 100, apiKey)
      } else {
        cat(paste0("Step 3: ", target_asset, " not supported by AAVE, holding in vault\n"))
      }
    } else if (target_aave$is_supplied) {
      cat(paste0("✅ ", target_asset, " already earning yield in AAVE\n"))
    }
    
    return(TRUE)
  }
  
  # ====================
  # SELL/NEUTRAL SIGNAL LOGIC
  # ====================
  else if (side == "sell" || side == "neutral" || side == "hold") {
    cat("📉 SELL/NEUTRAL signal detected\n\n")
    
    # Step 1: Check if target asset is supplied to AAVE - need to unlend it first
    if (target_aave$is_supplied) {
      cat(paste0("Step 1: Unlending ", target_asset, " from AAVE before selling...\n"))
      if (!unlend_from_aave(pool, target_asset, network, 100, apiKey)) {
        cat("❌ Failed to unlend asset, cannot proceed with trade\n")
        return(FALSE)
      }
      # Refresh composition after unlending
      pool_composition <- pool_comp(pool = pool, network = network, protocol = "dhedge")
      target_balance <- get_balance(pool_composition, target_asset, protocol = "dhedge")
    }
    
    # Step 2: Sell target asset if we have it
    if (target_balance > 0.001) {
      cat(paste0("Step 2: Selling ", target_asset, " to ", base_asset, "...\n"))
      trade_result <- trade(
        protocol = "dhedge",
        ep = "api",
        from = target_asset,
        to = base_asset,
        platform = platform,
        network = network,
        share = share,
        slippage = slippage,
        pool = pool,
        max_usd = max_usd,
        apiKey = apiKey
      )
      
      if (is.null(trade_result) || trade_result == "fail") {
        cat("❌ Trade failed\n")
        return(FALSE)
      }
      
      Sys.sleep(5)
      # Refresh composition after trade
      pool_composition <- pool_comp(pool = pool, network = network, protocol = "dhedge")
      base_balance <- get_balance(pool_composition, base_asset, protocol = "dhedge")
    }
    
    # Step 3: Lend USDC to AAVE if not already lent
    # Note: USDC is always supported by AAVE, so we don't check base_supported
    # This allows earning yield even when selling non-AAVE assets (MORPHO, SNX, etc.)
    if (base_balance > 1 && !base_aave$is_supplied) {
      cat(paste0("Step 3: Lending ", base_asset, " to AAVE to earn yield while waiting...\n"))
      lend_to_aave(pool, base_asset, network, 100, apiKey)
    } else if (base_aave$is_supplied) {
      cat(paste0("✅ ", base_asset, " already earning yield in AAVE\n"))
    }
    
    return(TRUE)
  }
  
  cat("ℹ️ No action needed for signal:", side, "\n")
  return(TRUE)
}

#' Execute standard trade without AAVE optimization (fallback)
execute_standard_trade <- function(pool, pair, side, network, share, slippage, platform, max_usd, apiKey) {
  parts <- strsplit(pair, "-")[[1]]
  
  if (side == "long" || side == "buy") {
    from <- parts[2]
    to <- parts[1]
  } else if (side == "sell" || side == "neutral") {
    from <- parts[1]
    to <- parts[2]
  } else {
    return(TRUE) # hold
  }
  
  trade_result <- trade(
    protocol = "dhedge",
    ep = "api",
    from = from,
    to = to,
    platform = platform,
    network = network,
    share = share,
    slippage = slippage,
    pool = pool,
    max_usd = max_usd,
    apiKey = apiKey
  )
  
  return(!is.null(trade_result) && trade_result != "fail")
}

cat("✅ AAVE Yield Optimizer loaded\n")
