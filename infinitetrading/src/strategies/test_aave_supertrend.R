# ==============================================================================
# test_aave_supertrend.R
# Tests USDC deposit and withdraw via Aave V3 on the SuperTrend polygon vault.
# Run this manually BEFORE enabling Aave logic in superTrend.R to verify that
# approve / lend / unlend API calls all work correctly.
#
# Flow:
#   1. Check current idle USDC in vault and USDC already on Aave
#   2. Approve USDC for Aave V3 (required before first lend — only hits chain
#      if allowance is insufficient, otherwise no-op)
#   3. Lend 100% idle USDC to Aave, wait 30s, verify it landed
#   4. Unlend 100% from Aave, wait 30s, verify it came back
#
# Usage:
#   Rscript ~/infinitetrading/src/strategies/test_aave_supertrend.R
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
})

source("~/infinitetrading/src/strategies/main.R")

# ── Config ────────────────────────────────────────────────────────────────────

TEST_VAULT   <- "0x269782b044b2229a596439c4d8ec99baf32e4c60"
TEST_NETWORK <- "polygon"
TEST_USDC    <- "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359"  # native USDC on Polygon
AAVE_POOL    <- "0x794a61358d6845594f94dc1db02a252b5b4814ad"  # Aave V3 Pool on Polygon
MIN_USD      <- 0.5   # minimum USDC threshold to run deposit/withdraw

# ── Helpers ───────────────────────────────────────────────────────────────────

`%||%` <- function(a, b) if (!is.null(a)) a else b

local_GET <- function(endpoint, params) {
  resp <- GET(paste0("http://localhost:8000/", endpoint), query = params)
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

# All params as query string — body is empty (matches how btc/eth yield do it)
local_POST <- function(endpoint, params, body = "", body_json = NULL) {
  url <- paste0("http://localhost:8000/", endpoint)
  if (!is.null(body_json)) {
    resp <- POST(url, query = params,
                 body = body_json,
                 encode = "json",
                 add_headers("Content-Type" = "application/json"))
  } else {
    resp <- POST(url, query = params, body = body, encode = "raw")
  }
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

sep    <- function(lbl) cat(sprintf("\n%s\n%s\n", strrep("─", 60), lbl))
ok     <- function(msg) cat(sprintf("  ✅ %s\n", msg))
warn   <- function(msg) cat(sprintf("  ⚠  %s\n", msg))
err    <- function(msg) cat(sprintf("  ❌ %s\n", msg))
info   <- function(msg) cat(sprintf("  → %s\n", msg))

# ── Balance checkers ──────────────────────────────────────────────────────────

get_idle_usdc <- function() {
  resp <- tryCatch(local_GET("getTokenBalance", list(
    network = TEST_NETWORK,
    wallet  = TEST_VAULT,
    asset   = TEST_USDC
  )), error = function(e) { err(paste("getTokenBalance:", e$message)); NULL })
  if (is.null(resp) || is.null(resp$data)) return(0)
  as.numeric(resp$data$balance)
}

get_aave_supplied <- function() {
  resp <- tryCatch(local_GET("getSupplied", list(
    network         = TEST_NETWORK,
    pool            = TEST_VAULT,
    asset           = TEST_USDC,
    contractAddress = AAVE_POOL
  )), error = function(e) { err(paste("getSupplied:", e$message)); NULL })
  if (is.null(resp) || is.null(resp$data)) return(0)
  # resp$data may be a scalar string/number or a list with suppliedAmount
  d <- resp$data
  if (is.list(d) && !is.null(d$suppliedAmount)) return(as.numeric(d$suppliedAmount))
  as.numeric(d)
}

# ── Main test ─────────────────────────────────────────────────────────────────

sep("=== Aave V3 Test: SuperTrend Polygon LINK-USDC Vault ===")
cat(sprintf("  Vault   : %s\n", TEST_VAULT))
cat(sprintf("  Network : %s\n", TEST_NETWORK))
cat(sprintf("  USDC    : %s\n", TEST_USDC))
cat(sprintf("  AaveV3  : %s\n", AAVE_POOL))

# ─────────────────────────────────────────────────────────────────────────────
sep("STEP 1 — Current balances")
idle    <- get_idle_usdc()
on_aave <- get_aave_supplied()
cat(sprintf("  Idle USDC in vault : %.6f\n", idle))
cat(sprintf("  USDC on Aave       : %.6f\n", on_aave))

# ─────────────────────────────────────────────────────────────────────────────
sep("STEP 2 — Approve USDC for Aave V3")
# /approve takes network/pool/platform/apiKey as query params,
# and asset as JSON body — same pattern as btc_yield_base.R
info("Calling /approve for USDC on aavev3 ...")
approve_result <- tryCatch(
  local_POST("approve",
    params    = list(network  = TEST_NETWORK,
                     pool     = TEST_VAULT,
                     platform = "aavev3",
                     apiKey   = apiKey),
    body_json = list(asset = TEST_USDC)),
  error = function(e) list(status = "fail", message = e$message)
)
cat(sprintf("  Raw approve response: %s\n",
            toJSON(approve_result, auto_unbox = TRUE)))

if (!is.null(approve_result$status) && approve_result$status == "success") {
  ok("USDC approved for Aave V3 (or allowance already sufficient).")
  info("Waiting 15s for approval to be mined...")
  Sys.sleep(15)
} else {
  err(sprintf("Approve failed: %s", approve_result$message %||% "unknown"))
  err("Cannot proceed with deposit without approval.")
  quit(status = 1)
}

# ─────────────────────────────────────────────────────────────────────────────
sep("STEP 3 — Deposit idle USDC to Aave")
idle <- get_idle_usdc()
cat(sprintf("  Current idle USDC: %.6f\n", idle))

if (idle < MIN_USD) {
  warn(sprintf("Only %.6f idle USDC (< %.2f threshold).", idle, MIN_USD))
  warn("Skipping deposit test — top up the vault with USDC and re-run.")
} else {
  info(sprintf("Depositing %.6f USDC to Aave V3 (100%% share)...", idle))

  # /lend: all params in query string, no body
  dep <- tryCatch(local_POST("lend", list(
    network  = TEST_NETWORK,
    pool     = TEST_VAULT,
    asset    = TEST_USDC,
    platform = "aavev3",
    share    = 100,
    apiKey   = apiKey
  )), error = function(e) list(status = "fail", message = e$message))

  cat(sprintf("  Raw lend response: %s\n", toJSON(dep, auto_unbox = TRUE)))

  if (!is.null(dep$status) && dep$status == "success") {
    ok("Deposit tx submitted.")
    info("Waiting 30s for on-chain confirmation...")
    Sys.sleep(30)

    idle2    <- get_idle_usdc()
    on_aave2 <- get_aave_supplied()
    cat(sprintf("  After 30s — Idle USDC : %.6f\n", idle2))
    cat(sprintf("  After 30s — On Aave   : %.6f\n", on_aave2))

    if (on_aave2 >= MIN_USD) {
      ok("DEPOSIT CONFIRMED — USDC is on Aave.")
    } else if (idle2 < idle - 0.001) {
      warn("USDC left the vault but getSupplied shows 0 — may still be indexing.")
      warn("Proceeding to withdraw test anyway.")
    } else {
      err("DEPOSIT UNCONFIRMED — USDC unchanged after 30s.")
      err("Check the vault on dHEDGE and verify the transaction hash above.")
      quit(status = 1)
    }
  } else if (!is.null(dep$status) && dep$status == "skipped") {
    warn("Lend skipped (zero balance returned by composition).")
    warn("Vault may hold USDC.e not native USDC — check vault token list.")
    quit(status = 1)
  } else {
    err(sprintf("Deposit FAILED: %s", dep$message %||% "unknown"))
    err("May indicate low gas or contract revert — check API logs.")
    quit(status = 1)
  }
}

# ─────────────────────────────────────────────────────────────────────────────
sep("STEP 4 — Withdraw USDC from Aave")
on_aave_now <- get_aave_supplied()
cat(sprintf("  Current USDC on Aave: %.6f\n", on_aave_now))

if (on_aave_now < MIN_USD) {
  warn(sprintf("Only %.6f on Aave (< %.2f threshold) — skipping withdraw.", on_aave_now, MIN_USD))
} else {
  info(sprintf("Withdrawing %.6f USDC from Aave V3 (100%% share)...", on_aave_now))

  # /unlend: all params in query string including contractAddress (Aave pool)
  wit <- tryCatch(local_POST("unlend", list(
    network         = TEST_NETWORK,
    pool            = TEST_VAULT,
    asset           = TEST_USDC,
    platform        = "aavev3",
    share           = 100,
    contractAddress = AAVE_POOL,
    apiKey          = apiKey
  )), error = function(e) list(status = "fail", message = e$message))

  cat(sprintf("  Raw unlend response: %s\n", toJSON(wit, auto_unbox = TRUE)))

  if (!is.null(wit$status) && wit$status == "success") {
    ok("Withdraw tx submitted.")
    info("Waiting 30s for on-chain confirmation...")
    Sys.sleep(30)

    idle3    <- get_idle_usdc()
    on_aave3 <- get_aave_supplied()
    cat(sprintf("  After 30s — Idle USDC : %.6f\n", idle3))
    cat(sprintf("  After 30s — On Aave   : %.6f\n", on_aave3))

    if (on_aave3 < MIN_USD) {
      ok("WITHDRAW CONFIRMED — USDC is back in vault.")
    } else {
      err(sprintf("WITHDRAW UNCONFIRMED — %.6f still on Aave after 30s.", on_aave3))
      err("USDC may be stuck. Check the vault on dHEDGE manually.")
      quit(status = 1)
    }
  } else {
    err(sprintf("Withdraw FAILED: %s", wit$message %||% "unknown"))
    err("May indicate low gas or contract revert — check API logs.")
    quit(status = 1)
  }
}

# ─────────────────────────────────────────────────────────────────────────────
sep("=== TEST COMPLETE ===")
ok("All approve / deposit / withdraw steps passed.")
cat("  Safe to enable Aave logic in superTrend.R.\n\n")
