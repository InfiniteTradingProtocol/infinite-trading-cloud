# ==============================================================================
# BTC Yield Base Strategy
# Vault: 0xb1569ec05aba57fd9256ba3816ae9221f23306ee (Base)
#
# Collateral: cbBTC only — lent to AAVE v3
#
# Yield platforms (in priority order):
#   1. GHO lending on AAVE (Base) — if GHO supply APY > USDC borrow APY + 2pp
#        → borrow USDC to HF=1.5, swap USDC→GHO in $1000 chunks, lend GHO
#   2. Fluid fUSDC / Compound V3 USDC — if spread > 0.5pp open
#   3. None — just hold cbBTC as collateral, do nothing
#
# Yield harvest: before every repay, surplus USDC → cbBTC → AAVE collateral
# HF safety: every 5 min — emergency unwind + repay if HF < 1.30
# All swaps chunked at $1000 max to stay within vault guard limits
# ==============================================================================

source("~/infinitetrading/src/strategies/main.R")
source("~/infinitetrading/src/utils/email_alerts.R")

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Alert state for HF: max 2 emails per day
hf_alert <- new.env(parent = emptyenv())
hf_alert$count <- 0L
hf_alert$date  <- Sys.Date()

# ── Constants ─────────────────────────────────────────────────────────────────
VAULT           <- "0xb1569ec05aba57fd9256ba3816ae9221f23306ee"
NETWORK         <- "base"
AAVE_POOL       <- "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5"
USDC            <- "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"   # USDC on Base
CBBTC           <- "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf"   # cbBTC on Base
GHO             <- "0x6bb7a212910682dcfdbd5bcbb3e28fb4e8da10ee"   # GHO on Base
COMPOUND_MARKET <- "0xb125E6687d4313864e53df431d5425969c15Eb2F"   # cUSDCv3 on Base
FLUID_MARKET    <- "0xf42f5795d9ac7e9d757db633d693cd548cfd9169"   # fUSDC on Base

# cbBTC is the only collateral asset for this vault
BTC_COLLATERAL_ASSETS <- c(CBBTC)

TARGET_HF          <- 1.50
HF_LOW             <- 1.30   # below this → reduce debt immediately
HF_HIGH            <- 1.70   # above this → borrow more (if active)
MIN_BORROW         <- 1.0    # minimum USD to bother borrowing/repaying
HF_INTERVAL_SECS   <- 300    # 5 minutes  – HF safety check cadence
APY_INTERVAL_SECS  <- 1800   # 30 minutes – spread/APY evaluation cadence
MAX_SWAP_USD       <- 1000   # maximum USD per single DEX swap chunk

# GHO spread thresholds (absolute percentage points above USDC borrow APY)
GHO_SPREAD_OPEN    <- 2.0    # pp required to open a GHO position
GHO_SPREAD_HOLD    <- 0.0    # pp required to hold (prevents churning)

# State file — JSON, persists across restarts
# Format: { "active_platform": "fluid"|"compound"|"gho"|"none", "approved": ["asset:market", ...] }
STATE_FILE <- "/home/ubuntu/infinitetrading/src/logs/btc_yield_base_state.json"

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
to_usdc_wei <- function(usd) {
  as.character(floor(usd * 1e6))
}

target_debt_usd <- function(collateral, liq_threshold, target_hf = TARGET_HF) {
  (collateral * liq_threshold) / target_hf
}

# ── One-time approvals ────────────────────────────────────────────────────────

# Approve cbBTC for AAVE lending (once — cached in state file)
ensure_cbbtc_approved_aave <- function() {
  if (is_approved(CBBTC, "aavev3")) {
    cat("  ℹ️  cbBTC already approved for AAVE (cached)\n")
    return(invisible(TRUE))
  }
  cat("  → Approving cbBTC for AAVE v3\n")
  url  <- paste0("http://localhost:8000/approve?network=", NETWORK,
                 "&pool=", VAULT, "&platform=aavev3&apiKey=", apiKey)
  resp <- POST(url, body = list(asset = CBBTC), encode = "json")
  result <- tryCatch(fromJSON(content(resp, "text", encoding = "UTF-8")),
                     error = function(e) list(status = "fail", message = e$message))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(CBBTC, "aavev3")
    cat("  ✅ cbBTC approved for AAVE\n")
    Sys.sleep(15)
    return(invisible(TRUE))
  }
  cat(sprintf("  ⚠️  cbBTC AAVE approval failed: %s\n", result$message %||% "unknown"))
  return(invisible(FALSE))
}

# Approve GHO for AAVE lending (once — cached in state file)
ensure_gho_approved_aave <- function() {
  if (is_approved(GHO, "aavev3")) {
    cat("  ℹ️  GHO already approved for AAVE (cached)\n")
    return(invisible(TRUE))
  }
  cat("  → Approving GHO for AAVE v3\n")
  url  <- paste0("http://localhost:8000/approve?network=", NETWORK,
                 "&pool=", VAULT, "&platform=aavev3&apiKey=", apiKey)
  resp <- POST(url, body = list(asset = GHO), encode = "json")
  result <- tryCatch(fromJSON(content(resp, "text", encoding = "UTF-8")),
                     error = function(e) list(status = "fail", message = e$message))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(GHO, "aavev3")
    cat("  ✅ GHO approved for AAVE\n")
    Sys.sleep(15)
    return(invisible(TRUE))
  }
  cat(sprintf("  ⚠️  GHO AAVE approval failed: %s\n", result$message %||% "unknown"))
  return(invisible(FALSE))
}

# Approve GHO for KyberSwap router (once — cached in state file)
ensure_gho_approved_kyberswap <- function() {
  if (is_approved(GHO, "kyberswap")) {
    cat("  ℹ️  GHO already approved for KyberSwap (cached)\n")
    return(invisible(TRUE))
  }
  cat("  → Approving GHO for KyberSwap\n")
  url  <- paste0("http://localhost:8000/approve?network=", NETWORK,
                 "&pool=", VAULT, "&platform=kyberswap&apiKey=", apiKey)
  resp <- POST(url, body = list(asset = GHO), encode = "json")
  result <- tryCatch(fromJSON(content(resp, "text", encoding = "UTF-8")),
                     error = function(e) list(status = "fail", message = e$message))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(GHO, "kyberswap")
    cat("  ✅ GHO approved for KyberSwap\n")
    Sys.sleep(15)
    return(invisible(TRUE))
  }
  cat(sprintf("  ⚠️  GHO KyberSwap approval failed: %s\n", result$message %||% "unknown"))
  return(invisible(FALSE))
}

# ── Action functions ──────────────────────────────────────────────────────────

lend_btc_collateral <- function() {
  tryCatch({
    result <- local_POST("lend", list(
      network  = NETWORK,
      pool     = VAULT,
      asset    = CBBTC,
      platform = "aavev3",
      share    = 100,
      apiKey   = apiKey
    ))
    if (!is.null(result$status) && result$status == "success") {
      cat("  ✅ cbBTC lent to AAVE\n")
      Sys.sleep(30)
    }
  }, error = function(e) {
    # Silently skip — already fully supplied or zero balance
  }, warning = function(w) {})
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

get_usdc_debt_wei <- function() {
  resp <- local_GET("getBorrowed", list(
    network         = NETWORK,
    pool            = VAULT,
    asset           = USDC,
    contractAddress = AAVE_POOL
  ))
  if (is.null(resp$data)) return(NULL)
  as.numeric(floor(as.numeric(resp$data) * 1e6))
}

# Verify the cached active_platform against actual vault token balances.
# Returns the (possibly corrected) platform string and resets the state file if wrong.
validate_platform_state <- function() {
  cached <- read_active_platform()
  if (cached == "none") return(invisible("none"))

  # For GHO: check the amount actually supplied to Aave via getSupplied
  if (cached == "gho") {
    gho_resp <- tryCatch(local_GET("getSupplied", list(
      network         = NETWORK,
      pool            = VAULT,
      asset           = GHO,
      contractAddress = AAVE_POOL
    )), error = function(e) NULL)
    Sys.sleep(2)
    gho_supplied <- if (!is.null(gho_resp$data)) as.numeric(gho_resp$data) else NA
    if (!is.na(gho_supplied) && gho_supplied < MIN_BORROW) {
      cat(sprintf("  ⚠️  State mismatch: cached 'gho' but aGHO supplied = $%.4f — resetting to none\n",
                  gho_supplied))
      clear_active_platform()
      return(invisible("none"))
    }
    cat(sprintf("  ✅ Platform validated: GHO (aGHO supplied = $%.4f)\n",
                if (is.na(gho_supplied)) 0 else gho_supplied))
    return(invisible("gho"))
  }

  check_asset <- switch(cached,
    fluid    = FLUID_MARKET,
    compound = COMPOUND_MARKET,
    NULL
  )
  if (is.null(check_asset)) return(invisible(cached))

  bal_resp <- tryCatch(local_GET("getTokenBalance", list(
    network = NETWORK, wallet = VAULT, asset = check_asset
  )), error = function(e) NULL)
  Sys.sleep(2)

  actual_balance <- if (!is.null(bal_resp$data)) as.numeric(bal_resp$data$balance) else NA

  if (!is.na(actual_balance) && actual_balance < MIN_BORROW) {
    cat(sprintf("  ⚠️  State mismatch: cached '%s' but vault holds $%.4f %s tokens — resetting to none\n",
                cached, actual_balance, toupper(cached)))
    clear_active_platform()
    return(invisible("none"))
  }

  cat(sprintf("  ✅ Platform validated: %s (vault holds $%.4f receipt tokens)\n",
              toupper(cached), if (is.na(actual_balance)) 0 else actual_balance))
  return(invisible(cached))
}


deposit_usdc_to_fluid <- function() {
  cat("  → Depositing all USDC to Fluid\n")
  already_approved <- is_approved(USDC, FLUID_MARKET)
  result <- local_POST("depositFluid", list(
    network     = NETWORK,
    pool        = VAULT,
    asset       = USDC,
    share       = 100,
    apiKey      = apiKey,
    skipApprove = if (already_approved) "true" else "false"
  ))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(USDC, FLUID_MARKET)
    return(TRUE)
  }
  cat(sprintf("  ⚠️  depositFluid failed: %s\n", result$message %||% "unknown error"))
  return(FALSE)
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
    network     = NETWORK,
    pool        = VAULT,
    asset       = USDC,
    share       = 100,
    apiKey      = apiKey,
    skipApprove = if (already_approved) "true" else "false"
  ))
  if (!is.null(result$status) && result$status == "success") {
    mark_approved(USDC, COMPOUND_MARKET)
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

# ── GHO helpers ───────────────────────────────────────────────────────────────

to_gho_wei <- function(usd) {
  format(floor(usd * 1e18), scientific = FALSE)
}

swap_usdc_to_gho_loop <- function(total_usd) {
  remaining <- total_usd
  cat(sprintf("  → Swapping $%.2f USDC → GHO in $%.0f chunks\n", total_usd, MAX_SWAP_USD))
  while (remaining > MIN_BORROW) {
    chunk_usd <- min(MAX_SWAP_USD, remaining)
    chunk_wei <- to_usdc_wei(chunk_usd)
    cat(sprintf("     chunk $%.2f USDC (remaining $%.2f)\n", chunk_usd, remaining))
    # Try kyberswap first, fall back to odos
    result <- tryCatch({
      local_GET("trade", list(
        network  = NETWORK,
        pool     = VAULT,
        platform = "kyberswap",
        from     = USDC,
        to       = GHO,
        amount   = chunk_wei,
        slippage = 1.0,
        apiKey   = apiKey
      ))
    }, error = function(e) list(status = "fail", msg = e$message))
    if (!is.null(result$status) && result$status != "success") {
      err_msg <- result$msg %||% result$message %||% "unknown"
      cat(sprintf("  ⚠️  KyberSwap USDC→GHO failed (%s) — trying odos\n", err_msg))
      result <- tryCatch({
        local_GET("trade", list(
          network  = NETWORK,
          pool     = VAULT,
          platform = "odos",
          from     = USDC,
          to       = GHO,
          amount   = chunk_wei,
          slippage = 1.0,
          maxPrice = 1,
          apiKey   = apiKey
        ))
      }, error = function(e) list(status = "fail", msg = e$message))
    }
    if (!is.null(result$status) && result$status == "success") {
      remaining <- remaining - chunk_usd
      Sys.sleep(30)
    } else {
      err_msg <- result$msg %||% result$message %||% "unknown"
      cat(sprintf("  ⚠️  USDC→GHO swap failed on all platforms: %s — aborting loop\n", err_msg))
      break
    }
  }
  cat("  ✅ USDC→GHO swap loop complete\n")
}

# Returns the vault's current GHO balance in USD (GHO ≈ $1 peg, 18 decimals)
get_gho_balance_usd <- function() {
  resp <- tryCatch(
    local_GET("getTokenBalance", list(network = NETWORK, wallet = VAULT, asset = GHO)),
    error = function(e) NULL
  )
  if (is.null(resp$data)) return(NULL)
  as.numeric(resp$data$balance)
}

# Try a single GHO→USDC chunk via one platform. Returns the parsed API result.
gho_swap_chunk <- function(chunk_wei, platform) {
  tryCatch({
    local_GET("trade", list(
      network  = NETWORK,
      pool     = VAULT,
      platform = platform,
      from     = GHO,
      to       = USDC,
      amount   = chunk_wei,
      slippage = 1.0,
      apiKey   = apiKey
    ))
  }, error = function(e) list(status = "fail", msg = e$message))
}

# Swap GHO → USDC in $MAX_SWAP_USD chunks. Returns TRUE if fully swapped, FALSE on failure.
# total_usd: amount to swap; if NULL uses actual vault GHO balance.
swap_gho_to_usdc_loop <- function(total_usd = NULL) {
  if (is.null(total_usd) || is.na(total_usd) || total_usd <= 0) {
    total_usd <- get_gho_balance_usd()
    if (is.null(total_usd) || total_usd <= 0) {
      cat("  ⚠️  GHO wallet balance is 0 or unavailable — nothing to swap\n")
      return(FALSE)
    }
    cat(sprintf("  ℹ️  Using actual GHO wallet balance: $%.4f\n", total_usd))
  }
  remaining <- total_usd
  cat(sprintf("  → Swapping $%.2f GHO → USDC in $%.0f chunks\n", total_usd, MAX_SWAP_USD))
  while (remaining > MIN_BORROW) {
    chunk_usd <- min(MAX_SWAP_USD, remaining)
    chunk_wei <- to_gho_wei(chunk_usd)
    cat(sprintf("     chunk $%.2f GHO (remaining $%.2f)\n", chunk_usd, remaining))

    # Try kyberswap first, fall back to odos
    result <- gho_swap_chunk(chunk_wei, "kyberswap")
    if (!is.null(result$status) && result$status != "success") {
      err_msg <- result$msg %||% result$message %||% "unknown"
      cat(sprintf("  ⚠️  KyberSwap GHO→USDC failed (%s) — trying odos\n", err_msg))
      result <- gho_swap_chunk(chunk_wei, "odos")
    }

    if (!is.null(result$status) && result$status == "success") {
      remaining <- remaining - chunk_usd
      Sys.sleep(30)
    } else {
      err_msg <- result$msg %||% result$message %||% "unknown"
      cat(sprintf("  ⚠️  GHO→USDC swap failed on all platforms: %s — aborting loop\n", err_msg))
      return(FALSE)   # caller must NOT clear state — GHO still in vault
    }
  }
  cat("  ✅ GHO→USDC swap loop complete\n")
  return(TRUE)
}

lend_gho <- function() {
  cat("  → Lending all GHO to AAVE\n")
  result <- local_POST("lend", list(
    network  = NETWORK,
    pool     = VAULT,
    asset    = GHO,
    platform = "aavev3",
    share    = 100,
    apiKey   = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  lend GHO failed: %s\n", result$message %||% "unknown"))
  }
  result
}

unlend_gho <- function() {
  cat("  → Withdrawing all GHO from AAVE\n")
  result <- local_POST("unlend", list(
    network         = NETWORK,
    pool            = VAULT,
    asset           = GHO,
    platform        = "aavev3",
    share           = 100,
    contractAddress = AAVE_POOL,
    apiKey          = apiKey
  ))
  if (!is.null(result$status) && result$status != "success") {
    cat(sprintf("  ⚠️  unlend GHO failed: %s\n", result$message %||% "unknown"))
  }
  result
}

# ── Yield harvest ─────────────────────────────────────────────────────────────
# Called BEFORE any repay. If vault holds more USDC than the on-chain debt
# (yield earned > borrow cost), swap the surplus to cbBTC and lend it to AAVE
# as additional collateral — compounding the BTC position.
# Threshold: only harvest if surplus > $5 to avoid wasting gas on dust.
MIN_HARVEST_USD <- 5.0

harvest_yield_surplus <- function() {
  debt_wei <- get_usdc_debt_wei()
  Sys.sleep(2)
  if (is.null(debt_wei) || debt_wei == 0) {
    cat("  ℹ️  No USDC debt — nothing to harvest\n")
    return(invisible(FALSE))
  }

  bal_resp <- local_GET("getTokenBalance", list(
    network = NETWORK,
    wallet  = VAULT,
    asset   = USDC
  ))
  Sys.sleep(2)
  if (is.null(bal_resp$data)) {
    cat("  ⚠️  Could not fetch vault USDC balance — skipping harvest\n")
    return(invisible(FALSE))
  }

  usdc_balance_usd <- as.numeric(bal_resp$data$balance)
  debt_usd         <- debt_wei / 1e6
  surplus          <- usdc_balance_usd - debt_usd

  cat(sprintf("  💰 Harvest check: vault USDC $%.4f  debt $%.4f  surplus $%.4f\n",
              usdc_balance_usd, debt_usd, surplus))

  if (surplus < MIN_HARVEST_USD) {
    cat(sprintf("  ℹ️  Surplus $%.4f < $%.0f threshold — skipping harvest\n", surplus, MIN_HARVEST_USD))
    return(invisible(FALSE))
  }

  cat(sprintf("  🌾 Harvesting $%.4f surplus USDC → cbBTC → AAVE collateral\n", surplus))

  swap_result <- tryCatch({
    local_GET("trade", list(
      network  = NETWORK,
      pool     = VAULT,
      platform = "odos",
      from     = USDC,
      to       = CBBTC,
      amount   = to_usdc_wei(surplus),
      slippage = 1,
      apiKey   = apiKey
    ))
  }, error = function(e) list(status = "fail", message = e$message))

  if (is.null(swap_result$status) || swap_result$status != "success") {
    cat(sprintf("  ⚠️  USDC→cbBTC harvest swap failed: %s — skipping\n",
                swap_result$message %||% "unknown"))
    return(invisible(FALSE))
  }

  cat("  ✅ Surplus swapped to cbBTC — lending to AAVE\n")
  Sys.sleep(20)
  lend_btc_collateral()
  cat("  ✅ Yield harvest complete\n")
  return(invisible(TRUE))
}

# Sweep idle GHO and USDC every cycle.
# - Idle GHO (not in a GHO position): swap to USDC via kyberswap
# - Idle USDC (no active protocol): repay debt; if debt clears, convert residual to cbBTC collateral
sweep_idle_assets <- function() {
  current_platform <- read_active_platform()

  # 1. Swap any GHO sitting in vault (not currently lent)
  if (current_platform != "gho") {
    idle_gho <- get_gho_balance_usd()
    if (!is.null(idle_gho) && idle_gho > MIN_BORROW) {
      cat(sprintf("  🧹 Idle GHO $%.4f in vault — swapping to USDC\n", idle_gho))
      swap_gho_to_usdc_loop(NULL)
      Sys.sleep(15)
    }
  }

  # 2. Handle idle USDC only when no protocol is holding it
  if (current_platform != "none") return(invisible(NULL))

  usdc_resp <- tryCatch(local_GET("getTokenBalance", list(
    network = NETWORK, wallet = VAULT, asset = USDC
  )), error = function(e) NULL)
  idle_usdc <- if (!is.null(usdc_resp$data)) as.numeric(usdc_resp$data$balance) else 0

  if (idle_usdc <= MIN_BORROW) return(invisible(NULL))

  Sys.sleep(2)
  aave_now <- tryCatch(local_GET("getPoolAaveData", list(
    network = NETWORK, pool = VAULT, contractAddress = AAVE_POOL
  )), error = function(e) NULL)
  current_debt <- if (!is.null(aave_now$data)) as.numeric(aave_now$data$totalDebtBase) else 0

  if (current_debt > MIN_BORROW) {
    cat(sprintf("  🧹 $%.4f idle USDC, $%.4f debt — repaying\n", idle_usdc, current_debt))
    repay_usdc_all()
    Sys.sleep(15)
    usdc_resp2 <- tryCatch(local_GET("getTokenBalance", list(
      network = NETWORK, wallet = VAULT, asset = USDC
    )), error = function(e) NULL)
    idle_usdc <- if (!is.null(usdc_resp2$data)) as.numeric(usdc_resp2$data$balance) else 0
  }

  if (idle_usdc > MIN_BORROW) {
    if (isTRUE(cached_profitable)) {
      # Spread still open — deploy USDC rather than converting to collateral
      plat <- cached_best_platform %||% "fluid"
      cat(sprintf("  🧹 $%.4f USDC idle, %s still profitable — deploying\n", idle_usdc, toupper(plat)))
      if (plat == "fluid") {
        ok <- deposit_usdc_to_fluid()
        if (ok) write_active_platform("fluid")
      } else {
        ok <- deposit_usdc_to_compound()
        if (ok) write_active_platform("compound") else {
          ok2 <- deposit_usdc_to_fluid()
          if (ok2) write_active_platform("fluid")
        }
      }
    } else {
      cat(sprintf("  🧹 $%.4f USDC no debt — converting to cbBTC collateral\n", idle_usdc))
      r <- tryCatch(local_GET("trade", list(
        network  = NETWORK, pool = VAULT, platform = "odos",
        from = USDC, to = CBBTC, amount = to_usdc_wei(idle_usdc), slippage = 1, apiKey = apiKey
      )), error = function(e) list(status = "fail", msg = e$message))
      if (!is.null(r$status) && r$status == "success") {
        Sys.sleep(20)
        lend_btc_collateral()
      } else {
        cat(sprintf("  ⚠️  USDC→cbBTC sweep failed: %s\n", r$msg %||% r$message %||% "unknown"))
      }
    }
  }
}

# ── Main loop ─────────────────────────────────────────────────────────────────
cat(rep("=", 70), "\n")
cat("BTC Yield Base Strategy starting\n")
cat(sprintf("Vault:  %s\n", VAULT))
cat(sprintf("Target HF: %.2f  |  Low: %.2f  |  High: %.2f\n", TARGET_HF, HF_LOW, HF_HIGH))
cat(sprintf("HF check: every %ds  |  APY check: every %ds\n", HF_INTERVAL_SECS, APY_INTERVAL_SECS))
cat(rep("=", 70), "\n\n")

# Run one-time startup approvals (idempotent — cached in state file)
cat("── Startup approvals ──\n")
ensure_cbbtc_approved_aave()
ensure_gho_approved_aave()
ensure_gho_approved_kyberswap()
cat("── Approvals complete ──\n\n")

# Asymmetric spread thresholds
MIN_SPREAD_OPEN <- 0.50
MIN_SPREAD_HOLD <- 0.00

# Minimum APY advantage Compound must have over Fluid (or vice versa) to justify
# a platform switch. Prevents churning when Compound's volatile APY briefly
# crosses Fluid's — the difference must be sustained and meaningful.
PLATFORM_SWITCH_MARGIN <- 1.5  # percentage points

# Cached APY state — updated every APY_INTERVAL_SECS
cached_profitable    <- FALSE
cached_best_platform <- "compound"
cached_spread        <- 0
gho_profitable       <- FALSE
gho_spread           <- 0
last_apy_check       <- Sys.time() - APY_INTERVAL_SECS - 1  # force check on first cycle

while (TRUE) {
  tryCatch({
    cat(sprintf("\n[%s] ── Cycle start ───────────────────────────────\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

    # 1. Lend any loose cbBTC collateral
    lend_btc_collateral()
    Sys.sleep(15)

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

    collateral <- as.numeric(aave$data$totalCollateralBase)
    debt       <- as.numeric(aave$data$totalDebtBase)
    hf         <- as.numeric(aave$data$healthFactor)
    liq_thresh <- as.numeric(aave$data$currentLiquidationThreshold)
    tgt_debt   <- target_debt_usd(collateral, liq_thresh)

    cat(sprintf("  AAVE → collateral $%.2f  debt $%.2f  HF %.4f  liqThresh %.2f\n",
                collateral, debt, hf, liq_thresh))
    cat(sprintf("  Target debt @ HF=%.2f → $%.2f\n", TARGET_HF, tgt_debt))

    active_platform <- validate_platform_state()
    cat(sprintf("  🗂️  State: active_platform = %s\n", active_platform))

    # ── Inline helpers ────────────────────────────────────────────────────────

    do_deposit <- function() {
      idle_usdc_resp <- tryCatch(local_GET("getTokenBalance", list(
        network = NETWORK, wallet = VAULT, asset = USDC
      )), error = function(e) NULL)
      idle_usdc <- if (!is.null(idle_usdc_resp$data)) as.numeric(idle_usdc_resp$data$balance) else 0
      if (is.na(idle_usdc) || idle_usdc <= MIN_BORROW) {
        cat(sprintf("  ℹ️  Skipping yield deposit: idle USDC $%.4f <= threshold $%.2f\n",
                    if (is.na(idle_usdc)) 0 else idle_usdc, MIN_BORROW))
        return(invisible(FALSE))
      }

      plat <- cached_best_platform
      if (plat == "fluid") {
        ok <- deposit_usdc_to_fluid()
        if (ok) write_active_platform("fluid") else cat("  ❌ Fluid deposit failed — state NOT updated\n")
      } else {
        ok <- deposit_usdc_to_compound()
        if (ok) {
          write_active_platform("compound")
        } else {
          cat("  ↩️  Compound failed — falling back to Fluid\n")
          ok2 <- deposit_usdc_to_fluid()
          if (ok2) write_active_platform("fluid") else cat("  ❌ Fluid fallback also failed — state NOT updated\n")
        }
      }
    }

    do_withdraw <- function() {
      if (active_platform == "fluid") {
        withdraw_usdc_from_fluid()
      } else if (active_platform == "compound") {
        withdraw_usdc_from_compound()
      } else if (active_platform == "gho") {
        unlend_gho()
      } else {
        cat("  ℹ️  No active yield position — nothing to withdraw\n")
      }
    }

    # ── 3. APY / spread check (every 15 minutes) ──────────────────────────────
    secs_since_apy <- as.numeric(difftime(Sys.time(), last_apy_check, units = "secs"))
    if (secs_since_apy >= APY_INTERVAL_SECS) {
      cat(sprintf("  📡 APY check (last was %.0fs ago)\n", secs_since_apy))

      fluid_apy_resp    <- local_GET("getSupplyAPY", list(platform = "fluid",    network = NETWORK, asset = USDC))
      Sys.sleep(2)
      compound_apy_resp <- local_GET("getSupplyAPY", list(platform = "compound", network = NETWORK, asset = USDC))
      Sys.sleep(2)
      gho_apy_resp      <- local_GET("getSupplyAPY", list(platform = "aave",     network = NETWORK, asset = GHO))
      Sys.sleep(2)
      aave_borrow_resp  <- local_GET("getBorrowAPY", list(platform = "aave",     network = NETWORK, asset = USDC))

      fluid_apy       <- as.numeric(fluid_apy_resp$data$apy_percent)
      compound_apy    <- as.numeric(compound_apy_resp$data$apy_percent)
      gho_apy         <- as.numeric(gho_apy_resp$data$apy_percent)
      aave_borrow_apy <- as.numeric(aave_borrow_resp$data$apy_percent)

      # GHO spread
      gho_spread      <<- gho_apy - aave_borrow_apy
      gho_should_open <- gho_spread > GHO_SPREAD_OPEN
      gho_should_hold <- gho_spread > GHO_SPREAD_HOLD
      gho_profitable  <<- if (active_platform == "gho") gho_should_hold else gho_should_open

      # Fluid/Compound spread
      best_apy             <- max(fluid_apy, compound_apy)
      # Symmetric hysteresis: prefer Fluid unless Compound is significantly better.
      # If already on Compound, only leave if Fluid beats it by PLATFORM_SWITCH_MARGIN.
      # If on Fluid/none/gho, only switch to Compound if it beats Fluid by PLATFORM_SWITCH_MARGIN.
      compound_advantage   <- compound_apy - fluid_apy
      cached_best_platform <<- if (active_platform == "compound") {
        if (compound_advantage >= -PLATFORM_SWITCH_MARGIN) "compound" else "fluid"
      } else {
        if (compound_advantage > PLATFORM_SWITCH_MARGIN) "compound" else "fluid"
      }
      cached_spread        <<- best_apy - aave_borrow_apy
      should_open          <- cached_spread > MIN_SPREAD_OPEN
      should_hold          <- cached_spread > MIN_SPREAD_HOLD
      cached_profitable    <<- if (active_platform %in% c("fluid","compound")) should_hold else should_open
      last_apy_check       <<- Sys.time()

      cat(sprintf("  APYs → GHO %.4f%%  Fluid %.4f%%  Compound %.4f%%  |  USDC borrow %.4f%%\n",
                  gho_apy, fluid_apy, compound_apy, aave_borrow_apy))
      cat(sprintf("  GHO spread: %.4f%%  (open>%.2f%% / hold>%.2f%%)  profitable=%s\n",
                  gho_spread, GHO_SPREAD_OPEN, GHO_SPREAD_HOLD, gho_profitable))
      cat(sprintf("  Fluid/Compound spread: %.4f%%  (open>%.2f%% / hold>%.2f%%)  best=%s  (Compound advantage %.2f%% vs margin %.1f%%)\n",
                  cached_spread, MIN_SPREAD_OPEN, MIN_SPREAD_HOLD, toupper(cached_best_platform),
                  compound_advantage, PLATFORM_SWITCH_MARGIN))

      # Skip all yield activity if collateral is zero (vault not yet funded)
      if (collateral < MIN_BORROW) {
        cat("  ℹ️  No collateral in vault — skipping yield logic\n")
      } else {

        # ── 3a. GHO takes top priority ────────────────────────────────────────
        if (gho_profitable) {

          if (active_platform != "gho") {
            cat(sprintf("  ✅ GHO spread %.4f%% > %.2f%% → opening GHO position\n", gho_spread, GHO_SPREAD_OPEN))

            if (active_platform %in% c("fluid", "compound")) {
              cat(sprintf("  🔄 Exiting %s before opening GHO\n", toupper(active_platform)))
              do_withdraw()
              Sys.sleep(30)
            }

            borrow_amt <- tgt_debt - debt
            if (borrow_amt > MIN_BORROW) {
              cat(sprintf("  → Borrowing $%.2f USDC to reach HF %.2f\n", borrow_amt, TARGET_HF))
              borrow_usdc(borrow_amt)
              Sys.sleep(30)
            }

            ensure_gho_approved_aave()

            total_to_swap <- if (borrow_amt > MIN_BORROW) tgt_debt else debt
            if (total_to_swap < MIN_BORROW) total_to_swap <- tgt_debt
            swap_usdc_to_gho_loop(total_to_swap)
            Sys.sleep(15)

            lend_gho()
            write_active_platform("gho")
            active_platform <- "gho"

          } else {
            cat(sprintf("  ✅ GHO spread %.4f%% → holding GHO position\n", gho_spread))

            # Sweep any idle USDC left in vault (e.g. from a failed swap during open)
            idle_usdc_resp <- tryCatch(local_GET("getTokenBalance", list(
              network = NETWORK, wallet = VAULT, asset = USDC
            )), error = function(e) NULL)
            idle_usdc <- if (!is.null(idle_usdc_resp$data)) as.numeric(idle_usdc_resp$data$balance) else 0
            if (idle_usdc > MIN_BORROW) {
              cat(sprintf("  💸 Found $%.4f idle USDC in vault — sweeping to GHO\n", idle_usdc))
              swap_usdc_to_gho_loop(idle_usdc)
              Sys.sleep(15)
              lend_gho()
              Sys.sleep(30)
            }

            # Re-lend any idle GHO sitting in vault (e.g. from a failed lend_gho() during open)
            idle_gho <- get_gho_balance_usd()
            if (!is.null(idle_gho) && idle_gho > MIN_BORROW) {
              cat(sprintf("  💸 Found $%.4f idle GHO in vault (not lent) — re-lending to AAVE\n", idle_gho))
              lend_gho()
              Sys.sleep(30)
            }

            if (debt < MIN_BORROW || hf > HF_HIGH) {
              borrow_amt <- tgt_debt - debt
              if (borrow_amt > MIN_BORROW) {
                cat(sprintf("  HF %.4f > %.2f → borrowing $%.2f more → swap → lend\n", hf, HF_HIGH, borrow_amt))
                borrow_usdc(borrow_amt)
                Sys.sleep(30)
                swap_usdc_to_gho_loop(borrow_amt)
                Sys.sleep(15)
                lend_gho()
              }
            }
          }

        } else if (active_platform == "gho") {
          # GHO no longer profitable — exit gracefully
          cat(sprintf("  ❌ GHO spread %.4f%% below hold threshold (%.2f%%) → exiting GHO\n",
                      gho_spread, GHO_SPREAD_HOLD))
          unlend_gho()
          Sys.sleep(30)
          # Use actual GHO wallet balance (not stale USDC debt)
          swap_ok <- swap_gho_to_usdc_loop(NULL)
          if (!swap_ok) {
            cat("  ⚠️  GHO→USDC swap failed — keeping state as 'gho', will retry next cycle\n")
          } else {
            Sys.sleep(30)
            harvest_yield_surplus()
            Sys.sleep(10)
            repay_usdc_all()
            Sys.sleep(10)
            clear_active_platform()
            active_platform <- "none"

            # Immediately re-enter Fluid/Compound if spread still profitable
            if (cached_profitable) {
              cat(sprintf("  \u21a9\ufe0f  Re-entering %s after GHO exit (spread %.4f%%)\n",
                          toupper(cached_best_platform), cached_spread))
              borrow_amt <- tgt_debt  # debt ≈ 0 after full repay
              if (borrow_amt > MIN_BORROW) {
                borrow_usdc(borrow_amt)
                Sys.sleep(30)
              }
              do_deposit()
            }
          }

        } else {
          # ── 3b. Fluid / Compound (GHO not profitable) ─────────────────────
          if (cached_profitable) {
            action_label <- if (active_platform != "none") "holding" else "opening"
            cat(sprintf("  ✅ Fluid/Compound spread %.4f%% → %s position [%s]\n",
                        cached_spread, action_label, toupper(cached_best_platform)))

            if (active_platform != "none" && active_platform != cached_best_platform) {
              cat(sprintf("  🔄 Switching from %s to %s\n", toupper(active_platform), toupper(cached_best_platform)))
              do_withdraw()
              Sys.sleep(30)
              do_deposit()
            } else if (active_platform == "none") {
              idle_usdc_resp <- tryCatch(local_GET("getTokenBalance", list(
                network = NETWORK, wallet = VAULT, asset = USDC
              )), error = function(e) NULL)
              idle_usdc_now <- if (!is.null(idle_usdc_resp$data)) as.numeric(idle_usdc_resp$data$balance) else 0

              if (!is.na(idle_usdc_now) && idle_usdc_now > MIN_BORROW) {
                cat(sprintf("  → Deploying idle USDC ($%.2f) to %s\n", idle_usdc_now, toupper(cached_best_platform)))
                do_deposit()
              } else {
                borrow_amt <- tgt_debt - debt
                if (borrow_amt > MIN_BORROW) {
                  cat(sprintf("  ℹ️  No idle USDC in wallet (%.4f). Borrowing $%.2f to deploy to %s\n",
                              if (is.na(idle_usdc_now)) 0 else idle_usdc_now, borrow_amt, toupper(cached_best_platform)))
                  borrow_usdc(borrow_amt)
                  Sys.sleep(30)
                  do_deposit()
                }
              }
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
            cat(sprintf("  ❌ Fluid/Compound spread %.4f%% below threshold → exiting\n", cached_spread))
            if (debt > MIN_BORROW) {
              cat(sprintf("  Debt $%.2f > 0 → withdrawing and repaying AAVE\n", debt))
              do_withdraw()
              Sys.sleep(30)
              harvest_yield_surplus()
              Sys.sleep(10)
              repay_usdc_all()
              Sys.sleep(10)
              clear_active_platform()
              active_platform <- "none"
              # Immediately convert any residual USDC to cbBTC collateral
              Sys.sleep(5)
              sweep_idle_assets()
            } else {
              cat("  No active position – holding cbBTC as collateral\n")
            }
          }
        } # end GHO / Fluid+Compound priority block

      } # end collateral > 0 guard

    } else {
      secs_until_apy <- ceiling(APY_INTERVAL_SECS - secs_since_apy)
      cat(sprintf("  ⏱ APY check in %ds | GHO spread cached %.4f%% | Fluid/Compound spread %.4f%% [%s]\n",
                  secs_until_apy, gho_spread %||% 0, cached_spread, toupper(cached_best_platform)))
    }

    # ── 4. HF SAFETY check (every cycle — EMERGENCY repay only) ──────────────
    active_platform <- read_active_platform()

    if (active_platform != "none" && debt > MIN_BORROW) {
      if (hf < HF_LOW) {
        cat(sprintf("  ⚠️  HF %.4f < %.2f → EMERGENCY: withdrawing and repaying to HF %.2f\n",
                    hf, HF_LOW, TARGET_HF))

        if (active_platform == "gho") {
          cat("  🔴 GHO emergency unwind\n")
          unlend_gho()
          Sys.sleep(30)
          # Use actual GHO wallet balance
          swap_gho_to_usdc_loop(NULL)
          Sys.sleep(30)
        } else {
          do_withdraw()
          Sys.sleep(30)
        }

        harvest_yield_surplus()
        Sys.sleep(10)

        actual_debt_wei <- get_usdc_debt_wei()
        if (!is.null(actual_debt_wei)) {
          aave_fresh <- local_GET("getPoolAaveData", list(
            network = NETWORK, pool = VAULT, contractAddress = AAVE_POOL
          ))
          if (!is.null(aave_fresh$data)) {
            fresh_tgt_debt_wei <- floor(target_debt_usd(
              as.numeric(aave_fresh$data$totalCollateralBase),
              as.numeric(aave_fresh$data$currentLiquidationThreshold)
            ) * 1e6)
          } else {
            fresh_tgt_debt_wei <- floor(tgt_debt * 1e6)
          }
          repay_amt_wei <- max(0, actual_debt_wei - fresh_tgt_debt_wei)

          # Cap repay to vault's actual USDC balance — partial swaps may leave
          # less USDC than the calculated repay amount, causing the tx to revert
          usdc_bal_resp <- tryCatch(local_GET("getTokenBalance", list(
            network = NETWORK, wallet = VAULT, asset = USDC
          )), error = function(e) NULL)
          if (!is.null(usdc_bal_resp$data)) {
            available_usdc_wei <- floor(as.numeric(usdc_bal_resp$data$balance) * 1e6)
            if (repay_amt_wei > available_usdc_wei) {
              cat(sprintf("  ⚠️  Repay capped: wanted %.0f wei but vault only has %.0f wei USDC\n",
                          repay_amt_wei, available_usdc_wei))
              repay_amt_wei <- available_usdc_wei
            }
          }

          cat(sprintf("  Fresh USDC debt: %.0f wei  tgt: %.0f wei  repaying: %.0f wei\n",
                      actual_debt_wei, fresh_tgt_debt_wei, repay_amt_wei))
          if (repay_amt_wei > 0) {
            result <- local_POST("repay", list(
              network  = NETWORK,
              pool     = VAULT,
              asset    = USDC,
              platform = "aavev3",
              amount   = as.character(repay_amt_wei),
              apiKey   = apiKey
            ))
            if (!is.null(result$status) && result$status != "success") {
              cat(sprintf("  ⚠️  repay failed: %s\n", result$message))
            }
          } else {
            cat("  ⚠️  No USDC available to repay — vault balance is zero\n")
          }
        } else {
          cat("  ⚠️  Could not fetch on-chain debt — falling back to stale estimate\n")
          repay_usdc(debt - tgt_debt)
        }
        Sys.sleep(30)

        # Re-enter if spread still profitable after repay
        if (active_platform == "gho" && !is.null(gho_profitable) && gho_profitable) {
          cat("  ↩️  Re-entering GHO position after emergency repay\n")
          aave_post <- local_GET("getPoolAaveData", list(
            network = NETWORK, pool = VAULT, contractAddress = AAVE_POOL
          ))
          if (!is.null(aave_post$data)) {
            post_debt     <- as.numeric(aave_post$data$totalDebtBase)
            post_tgt_debt <- target_debt_usd(
              as.numeric(aave_post$data$totalCollateralBase),
              as.numeric(aave_post$data$currentLiquidationThreshold)
            )
            borrow_amt <- max(0, post_tgt_debt - post_debt)
            if (borrow_amt > MIN_BORROW) {
              borrow_usdc(borrow_amt); Sys.sleep(30)
              swap_usdc_to_gho_loop(borrow_amt); Sys.sleep(15)
              lend_gho()
              write_active_platform("gho")
            }
          }
        } else if (cached_profitable) {
          do_deposit()
        } else {
          clear_active_platform()
        }

        # ── Post-emergency HF alert ────────────────────────────────────────────
        # Re-check HF after the full repay+re-entry cycle; alert if still critical
        tryCatch({
          aave_check <- local_GET("getPoolAaveData", list(
            network = NETWORK, pool = VAULT, contractAddress = AAVE_POOL
          ))
          hf_after <- if (!is.null(aave_check$data)) as.numeric(aave_check$data$healthFactor) else hf
          if (hf_after < HF_LOW && can_send_alert(hf_alert)) {
            send_resend_email(
              subject   = sprintf("\U0001f6a8 BTC Vault HF Critical: %.4f", hf_after),
              html_body = sprintf(paste0(
                "<h2>&#128680; Health Factor Still Critical</h2>",
                "<p><strong>Strategy:</strong> BTC Yield Base</p>",
                "<p><strong>Vault:</strong> %s</p>",
                "<p><strong>Health Factor:</strong> <span style='color:red'>%.4f</span> ",
                "(minimum safe: %.2f)</p>",
                "<p>Emergency repay was attempted but HF remains below threshold. ",
                "Manual intervention may be required.</p>",
                "<p><em>%s UTC</em></p>"
              ), VAULT, hf_after, HF_LOW, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
            )
            hf_alert$count <- hf_alert$count + 1L
          }
        }, error = function(e) {})

      } else {
        cat(sprintf("  HF %.4f in range [%.2f, %.2f] – safe\n", hf, HF_LOW, HF_HIGH))
      }
    }

    # ── 5. Sweep idle GHO / USDC ─────────────────────────────────────────────────────────
    sweep_idle_assets()

    cat(sprintf("[%s] ── Cycle complete. Sleeping %ds ──\n",
                format(Sys.time(), "%Y-%m-%d %H:%M:%S"), HF_INTERVAL_SECS))

  }, error = function(e) {
    cat(sprintf("❌ Unhandled error: %s\n", e$message))
  })

  Sys.sleep(HF_INTERVAL_SECS)
}
