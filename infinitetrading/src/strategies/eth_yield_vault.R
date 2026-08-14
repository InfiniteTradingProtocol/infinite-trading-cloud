# ==============================================================================
# ETH Yield Vault Strategy
# Vault: 0x54db076bfac96c02e9a2a66410d69f35ac481fe6 (Base)
#
# Logic (runs every 15 minutes):
#   - If any wstETH is loose in vault → lend it to AAVE
#   - If Fluid USDC supply APY > AAVE USDC borrow APY:
#       → Borrow USDC on AAVE until HF = 1.75, deposit all to Fluid
#       → If HF > 2.0 → borrow more to reach 1.75
#       → If HF < 1.5 → withdraw from Fluid, repay AAVE back to HF 1.75
#   - If Fluid USDC supply APY <= AAVE USDC borrow APY:
#       → Withdraw all from Fluid, repay all AAVE debt
# ==============================================================================

source("~/infinitetrading/src/strategies/main.R")

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ── Constants ─────────────────────────────────────────────────────────────────
VAULT         <- "0x54db076bfac96c02e9a2a66410d69f35ac481fe6"
NETWORK       <- "base"
AAVE_POOL     <- "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5"
USDC          <- "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"   # USDC on Base
WSTETH        <- "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452"   # wstETH on Base
WEETH         <- "0x04c0599ae5a44757c0af6f9ec3b93da8976c150a"   # weETH on Base
CBETH         <- "0x2ae3f1ec7f1f5012cfeab0185bfc7aa3cf0dec22"   # cbETH on Base
WETH          <- "0x4200000000000000000000000000000000000006"   # WETH on Base
COMPOUND_MARKET <- "0xb125E6687d4313864e53df431d5425969c15Eb2F"  # cUSDCv3 on Base

# All ETH-derivative tokens to lend as AAVE collateral (checked in order)
ETH_COLLATERAL_ASSETS <- c(WSTETH, WEETH, CBETH, WETH)

TARGET_HF          <- 1.50
HF_LOW             <- 1.30   # below this → reduce debt immediately
HF_HIGH            <- 1.70   # above this → borrow more (if active)
MIN_BORROW         <- 1.0    # minimum USD to bother borrowing/repaying
HF_INTERVAL_SECS   <- 300    # 5 minutes  – HF safety check cadence
APY_INTERVAL_SECS  <- 900    # 15 minutes – spread/APY evaluation cadence

# State file — JSON, persists across restarts
# Format: { "active_platform": "fluid"|"compound"|"none", "approved": ["asset:market", ...] }
STATE_FILE <- "/home/ubuntu/infinitetrading/src/logs/eth_yield_vault_state.json"

read_state <- function() {
  if (!file.exists(STATE_FILE)) return(list(active_platform = "none", approved = list()))
  tryCatch({
    s <- fromJSON(STATE_FILE)
    list(
      active_platform = s$active_platform %||% "none",
      approved        = as.list(s$approved %||% list())
    )
  }, error = function(e) list(active_platform = "none", approved = list()))
}

write_state <- function(state) {
  writeLines(toJSON(state, auto_unbox = TRUE), STATE_FILE)
}

read_active_platform <- function() read_state()$active_platform

write_active_platform <- function(platform) {
  s <- read_state()
  s$active_platform <- platform
  write_state(s)
  cat(sprintf("  📝 State saved: active_platform = %s\n", platform))
}

clear_active_platform <- function() write_active_platform("none")

is_approved <- function(asset, market) {
  key <- paste0(tolower(asset), ":", tolower(market))
  key %in% unlist(read_state()$approved)
}

mark_approved <- function(asset, market) {
  key <- paste0(tolower(asset), ":", tolower(market))
  s <- read_state()
  if (!key %in% unlist(s$approved)) {
    s$approved <- c(unlist(s$approved), key)
    write_state(s)
    cat(sprintf("  📝 Approval cached: %s\n", key))
  }
}

# ── Local API helpers (call Express directly, returns parsed list) ────────────
local_GET <- function(endpoint, params) {
  url <- paste0("http://localhost:8000/", endpoint)
  resp <- GET(url, query = params)
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

local_POST <- function(endpoint, params) {
  url <- paste0("http://localhost:8000/", endpoint)
  resp <- POST(url, query = params, body = "", encode = "raw")
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

# ── Math helpers ──────────────────────────────────────────────────────────────
# Convert USD amount (numeric) to USDC wei string (6 decimals, floored)
to_usdc_wei <- function(usd) {
  as.character(floor(usd * 1e6))
}

# From pool data, compute the USDC debt we should have for a given HF
target_debt_usd <- function(collateral, liq_threshold, target_hf = TARGET_HF) {
  (collateral * liq_threshold) / target_hf
}

# ── Action functions ──────────────────────────────────────────────────────────

lend_eth_collateral <- function() {
  asset_names <- c("wstETH", "weETH", "cbETH", "WETH")
  for (i in seq_along(ETH_COLLATERAL_ASSETS)) {
    asset   <- ETH_COLLATERAL_ASSETS[i]
    aname   <- asset_names[i]
    tryCatch({
      result <- local_POST("lend", list(
        network  = NETWORK,
        pool     = VAULT,
        asset    = asset,
        platform = "aavev3",
        share    = 100,
        apiKey   = apiKey
      ))
      if (!is.null(result$status) && result$status == "success") {
        cat(sprintf("  ✅ %s lent to AAVE\n", aname))
        Sys.sleep(30)  # wait for lend tx to confirm before moving on
      }
    }, error = function(e) {
      # Silently skip – asset not in vault or already fully supplied
    }, warning = function(w) {})
  }
}

borrow_usdc <- function(amount_usd) {
  cat(sprintf("  → Borrowing $%.2f USDC from AAVE\n", amount_usd))
  result <- local_POST("borrow", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    platform = "aavev3",
    amount   = to_usdc_wei(amount_usd),
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  borrow failed: %s\n", result$message))
  }
  result
}

repay_usdc <- function(amount_usd) {
  cat(sprintf("  → Repaying $%.2f USDC to AAVE\n", amount_usd))
  result <- local_POST("repay", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    platform = "aavev3",
    amount   = to_usdc_wei(amount_usd),
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  repay failed: %s\n", result$message))
  }
  result
}

repay_usdc_all <- function() {
  cat("  → Repaying ALL USDC debt to AAVE\n")
  result <- local_POST("repay", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    platform = "aavev3",
    share    = 100,
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  full repay failed: %s\n", result$message))
  }
  result
}

deposit_usdc_to_fluid <- function() {
  cat("  → Depositing all USDC to Fluid\n")
  result <- local_POST("depositFluid", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    share    = 100,
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  depositFluid failed: %s\n", result$message))
  }
  result
}

withdraw_usdc_from_fluid <- function() {
  cat("  → Withdrawing all USDC from Fluid\n")
  result <- local_POST("withdrawFluid", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    share    = 100,
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  withdrawFluid failed: %s\n", result$message))
  }
  result
}

deposit_usdc_to_compound <- function() {
  cat("  → Depositing all USDC to Compound V3\n")
  already_approved <- is_approved(USDC, COMPOUND_MARKET)
  result <- local_POST("depositCompoundV3", list(
    network          = NETWORK,
    pool             = VAULT,
    asset            = USDC,
    share            = 100,
    apiKey           = apiKey,
    skipApprove      = if (already_approved) "true" else "false"
  ))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(USDC, COMPOUND_MARKET)  # cache approval so we skip next time
    return(TRUE)
  }
  cat(sprintf("  ⚠️  depositCompoundV3 failed: %s\n", result$message %||% "unknown error"))
  return(FALSE)
}

withdraw_usdc_from_compound <- function() {
  cat("  → Withdrawing all USDC from Compound V3\n")
  result <- local_POST("withdrawCompoundV3", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = USDC,
    share    = 100,
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  withdrawCompoundV3 failed: %s\n", result$message))
  }
  result
}

# ── Main loop ─────────────────────────────────────────────────────────────────
cat(rep("=", 70), "\n")
cat("ETH Yield Vault Strategy starting\n")
cat(sprintf("Vault:  %s\n", VAULT))
cat(sprintf("Target HF: %.2f  |  Low: %.2f  |  High: %.2f\n", TARGET_HF, HF_LOW, HF_HIGH))
cat(sprintf("HF check: every %ds  |  APY check: every %ds\n", HF_INTERVAL_SECS, APY_INTERVAL_SECS))
cat(rep("=", 70), "\n\n")

# Asymmetric spread thresholds to avoid churning on volatile APYs
MIN_SPREAD_OPEN <- 0.50   # % spread required to open a fresh position
MIN_SPREAD_HOLD <- 0.00   # % spread below which we close an existing position

# Cached APY state — updated every APY_INTERVAL_SECS
cached_profitable    <- FALSE
cached_best_platform <- "compound"
cached_spread        <- 0
last_apy_check       <- Sys.time() - APY_INTERVAL_SECS - 1  # force check on first cycle

while (TRUE) {
  tryCatch({
    cat(sprintf("\n[%s] ── Cycle start ───────────────────────────────\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

    # 1. Lend any loose ETH-derivative collateral (wstETH, weETH, cbETH, WETH)
    lend_eth_collateral()
    Sys.sleep(15)  # settle before reading AAVE state

    # 2. Fetch AAVE pool state (every cycle — needed for HF safety)
    aave <- local_GET("getPoolAaveData", list(
      network         = NETWORK,
      pool            = VAULT,
      contractAddress = AAVE_POOL
    ))

    if (is.null(aave$data)) {
      cat("⚠️  Could not fetch AAVE pool data – skipping cycle\n")
      Sys.sleep(HF_INTERVAL_SECS)
      next
    }

    collateral   <- as.numeric(aave$data$totalCollateralBase)
    debt         <- as.numeric(aave$data$totalDebtBase)
    hf           <- as.numeric(aave$data$healthFactor)
    liq_thresh   <- as.numeric(aave$data$currentLiquidationThreshold)
    tgt_debt     <- target_debt_usd(collateral, liq_thresh)

    cat(sprintf("  AAVE → collateral $%.2f  debt $%.2f  HF %.4f  liqThresh %.2f\n",
                collateral, debt, hf, liq_thresh))
    cat(sprintf("  Target debt @ HF=%.2f → $%.2f\n", TARGET_HF, tgt_debt))

    active_platform <- read_active_platform()
    cat(sprintf("  🗂️  State: active_platform = %s\n", active_platform))

    # ── Helpers (use active_platform and cached_best_platform from closure) ──

    do_deposit <- function() {
      plat <- cached_best_platform
      if (plat == "fluid") {
        deposit_usdc_to_fluid()
        write_active_platform("fluid")
      } else {
        ok <- deposit_usdc_to_compound()
        if (ok) {
          write_active_platform("compound")
        } else {
          cat("  ↩️  Compound failed — falling back to Fluid\n")
          deposit_usdc_to_fluid()
          write_active_platform("fluid")
        }
      }
    }

    do_withdraw <- function() {
      if (active_platform == "fluid") {
        withdraw_usdc_from_fluid()
      } else if (active_platform == "compound") {
        withdraw_usdc_from_compound()
      } else {
        cat("  ℹ️  No active yield position — nothing to withdraw\n")
      }
    }

    # ── 3. APY / spread check (every 15 minutes) ──────────────────────────────
    secs_since_apy <- as.numeric(difftime(Sys.time(), last_apy_check, units = "secs"))
    if (secs_since_apy >= APY_INTERVAL_SECS) {
      cat(sprintf("  📡 APY check (last was %.0fs ago)\n", secs_since_apy))

      fluid_apy_resp    <- local_GET("getSupplyAPY",  list(platform = "fluid",    network = NETWORK, asset = USDC))
      compound_apy_resp <- local_GET("getSupplyAPY",  list(platform = "compound", network = NETWORK, asset = USDC))
      aave_borrow_resp  <- local_GET("getBorrowAPY",  list(platform = "aave",     network = NETWORK, asset = USDC))

      fluid_apy       <- as.numeric(fluid_apy_resp$data$apy_percent)
      compound_apy    <- as.numeric(compound_apy_resp$data$apy_percent)
      aave_borrow_apy <- as.numeric(aave_borrow_resp$data$apy_percent)

      best_apy             <- max(fluid_apy, compound_apy)
      cached_best_platform <<- ifelse(fluid_apy >= compound_apy, "fluid", "compound")
      cached_spread        <<- best_apy - aave_borrow_apy
      should_open          <- cached_spread > MIN_SPREAD_OPEN
      should_hold          <- cached_spread > MIN_SPREAD_HOLD
      cached_profitable    <<- if (active_platform != "none") should_hold else should_open
      last_apy_check       <<- Sys.time()

      cat(sprintf("  APYs → Fluid %.4f%%  Compound %.4f%%  |  AAVE borrow %.4f%%\n",
                  fluid_apy, compound_apy, aave_borrow_apy))
      cat(sprintf("  Best yield: %s @ %.4f%%  |  Spread: %.4f%%  (open>%.2f%% / hold>%.2f%%)\n",
                  toupper(cached_best_platform), best_apy, cached_spread, MIN_SPREAD_OPEN, MIN_SPREAD_HOLD))

      # ── Open/close decision based on fresh APY data ──
      if (cached_profitable) {
        action_label <- if (active_platform != "none") "holding" else "opening"
        cat(sprintf("  ✅ Spread %.4f%% → %s position [%s]\n",
                    cached_spread, action_label, toupper(cached_best_platform)))

        # Switch platforms if the better one changed
        if (active_platform != "none" && active_platform != cached_best_platform) {
          cat(sprintf("  🔄 Switching from %s to %s\n", toupper(active_platform), toupper(cached_best_platform)))
          do_withdraw()
          Sys.sleep(30)
          do_deposit()
        } else if (debt < MIN_BORROW || hf > HF_HIGH) {
          borrow_amt <- tgt_debt - debt
          if (borrow_amt > MIN_BORROW) {
            cat(sprintf("  HF %.4f > %.2f (or no debt) → borrowing $%.2f\n", hf, HF_HIGH, borrow_amt))
            borrow_usdc(borrow_amt)
            Sys.sleep(30)
            do_deposit()
          }
        }
      } else {
        cat(sprintf("  ❌ Spread %.4f%% below hold threshold (%.2f%%) → exiting position\n",
                    cached_spread, MIN_SPREAD_HOLD))
        if (debt > MIN_BORROW) {
          cat(sprintf("  Debt $%.2f > 0 → withdrawing and repaying AAVE\n", debt))
          do_withdraw()
          Sys.sleep(30)
          repay_usdc_all()
          Sys.sleep(10)
          clear_active_platform()
          active_platform <- "none"
        } else {
          cat("  No active position – idle\n")
        }
      }

    } else {
      secs_until_apy <- ceiling(APY_INTERVAL_SECS - secs_since_apy)
      cat(sprintf("  ⏱ APY check in %ds | cached spread %.4f%% [%s]\n",
                  secs_until_apy, cached_spread, toupper(cached_best_platform)))
    }

    # ── 4. HF SAFETY check (every cycle — EMERGENCY repay only) ──────────────
    # NOTE: "borrow more when HF > HF_HIGH" is handled in section 3 (APY check)
    # only. Never borrow here, to avoid double-borrowing on APY check cycles
    # (hf/debt here are from the start of the cycle and may be stale).
    # Re-read active_platform in case it changed above
    active_platform <- read_active_platform()

    if (active_platform != "none" && debt > MIN_BORROW) {
      if (hf < HF_LOW) {
        repay_amt <- debt - tgt_debt
        cat(sprintf("  ⚠️  HF %.4f < %.2f → EMERGENCY: repaying $%.2f to reach HF %.2f\n",
                    hf, HF_LOW, repay_amt, TARGET_HF))
        do_withdraw()
        Sys.sleep(30)
        repay_usdc(repay_amt)
        Sys.sleep(30)
        if (cached_profitable) do_deposit()
      } else {
        cat(sprintf("  HF %.4f in range [%.2f, %.2f] – safe\n", hf, HF_LOW, HF_HIGH))
      }
    }

    cat(sprintf("[%s] ── Cycle complete. Sleeping %ds ──\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S"), HF_INTERVAL_SECS))

  }, error = function(e) {
    cat(sprintf("❌ Unhandled error: %s\n", e$message))
  })

  Sys.sleep(HF_INTERVAL_SECS)
}
