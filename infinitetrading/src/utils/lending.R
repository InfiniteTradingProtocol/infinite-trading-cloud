# ==============================================================================
# utils/lending.R — Shared Aave V3 lend/unlend helpers
#
# Source this once in any strategy that needs Aave lending.
# Requires: httr + jsonlite already loaded, email_alerts.R already sourced.
#
# Global approval cache: one JSON file shared across all strategies.
# Key format: "network:vault:asset:platform" (all lower-case)
# ==============================================================================

LENDING_CACHE_FILE <- "/home/ubuntu/infinitetrading/src/logs/lending_approvals.json"
LENDING_MIN_USD    <- 0.5    # ignore balances below this (dust threshold)

# ── Address lookup tables ─────────────────────────────────────────────────────
# Maps token symbol + network → contract address.
# Add entries here to support new tokens/networks in any strategy.
.LENDING_TOKEN_ADDRS <- list(
  usdc = list(
    mainnet  = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    polygon  = "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359",
    base     = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
    optimism = "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
    arbitrum = "0xaf88d065e77c8cc2239327c5edb3a432268e5831"
  ),
  `usdc.e` = list(
    polygon  = "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
    optimism = "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
    arbitrum = "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8"
  )
)

# Aave V3 Pool contract per network.
.LENDING_AAVE_POOLS <- list(
  mainnet  = "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
  polygon  = "0x794a61358d6845594f94dc1db02a252b5b4814ad",
  base     = "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
  optimism = "0x794a61358d6845594f94dc1db02a252b5b4814ad",
  arbitrum = "0x794a61358d6845594f94dc1db02a252b5b4814ad"
)

# Normalise network name: "ethereum" and "eth" are aliases for "mainnet".
.lending_normalise_network <- function(network) {
  net <- tolower(trimws(network))
  if (net %in% c("ethereum", "eth")) "mainnet" else net
}

lending_resolve_asset <- function(network, token) {
  net   <- .lending_normalise_network(network)
  addrs <- .LENDING_TOKEN_ADDRS[[tolower(token)]]
  if (is.null(addrs)) stop(sprintf("[lending.R] Unknown token '%s'", token))
  addr  <- addrs[[net]]
  if (is.null(addr))  stop(sprintf("[lending.R] Token '%s' not mapped for network '%s'", token, network))
  addr
}

lending_resolve_aave_pool <- function(network) {
  net  <- .lending_normalise_network(network)
  pool <- .LENDING_AAVE_POOLS[[net]]
  if (is.null(pool)) stop(sprintf("[lending.R] No Aave V3 pool mapped for network '%s'", network))
  pool
}

# ── Cache helpers ─────────────────────────────────────────────────────────────

.lending_read_cache <- function() {
  if (!file.exists(LENDING_CACHE_FILE)) return(list(approved = character(0)))
  tryCatch({
    raw <- fromJSON(LENDING_CACHE_FILE)
    list(approved = as.character(raw$approved %||% character(0)))
  }, error = function(e) list(approved = character(0)))
}

.lending_write_cache <- function(cache) {
  dir.create(dirname(LENDING_CACHE_FILE), showWarnings = FALSE, recursive = TRUE)
  writeLines(toJSON(cache, auto_unbox = TRUE), LENDING_CACHE_FILE)
}

.lending_key <- function(network, vault, asset, platform) {
  paste(tolower(network), tolower(vault), tolower(asset), tolower(platform),
        sep = ":")
}

lending_is_approved <- function(network, vault, asset, platform) {
  .lending_key(network, vault, asset, platform) %in% .lending_read_cache()$approved
}

lending_mark_approved <- function(network, vault, asset, platform) {
  key   <- .lending_key(network, vault, asset, platform)
  cache <- .lending_read_cache()
  if (!key %in% cache$approved) {
    cache$approved <- c(cache$approved, key)
    .lending_write_cache(cache)
    cat(sprintf("  📝 Approval cached: %s\n", key))
  }
}

.lending_response_message <- function(result) {
  if (is.null(result)) return("error")
  msg <- result$message %||% result$msg %||% "error"
  paste(as.character(msg), collapse = " ")
}

.lending_is_allowance_error <- function(message) {
  grepl("allowance|approve|transfer amount exceeds", tolower(message))
}

.lending_is_transient_or_payment_error <- function(message) {
  grepl(
    paste(
      "infrastructure error", "read only property", "cannot assign", "is not a function",
      "cannot read", "typeerror", "etimedout", "econnrefused", "enotfound",
      "network error", "server_error", "status code 402", "insufficient gas",
      "insufficient funds", "payment required",
      sep = "|"
    ),
    tolower(message)
  )
}

# ── HTTP helpers ──────────────────────────────────────────────────────────────

.lending_GET <- function(endpoint, params) {
  resp <- GET(paste0("http://localhost:8000/", endpoint), query = params)
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

# All trade params go in query string (matches how btc/eth yield strategies call).
# body_json: named list sent as JSON body (used only by /approve which needs asset in body).
.lending_POST <- function(endpoint, params, body_json = NULL) {
  url <- paste0("http://localhost:8000/", endpoint)
  if (!is.null(body_json)) {
    resp <- POST(url, query = params,
                 body   = body_json,
                 encode = "json",
                 add_headers("Content-Type" = "application/json"))
  } else {
    resp <- POST(url, query = params, body = "", encode = "raw")
  }
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

# ── Balance readers ───────────────────────────────────────────────────────────

# Returns idle token balance in vault (human-readable units, e.g. 2.5 USDC).
lending_get_idle <- function(network, vault, asset) {
  resp <- tryCatch(
    .lending_GET("getTokenBalance", list(network = network,
                                        wallet  = vault,
                                        asset   = asset)),
    error = function(e) NULL)
  if (is.null(resp) || is.null(resp$data)) return(0)
  as.numeric(resp$data$balance %||% 0)
}

# Returns amount currently supplied to Aave (human-readable units).
lending_get_supplied <- function(network, vault, asset, aave_pool) {
  resp <- tryCatch(
    .lending_GET("getSupplied", list(network         = network,
                                    pool            = vault,
                                    asset           = asset,
                                    contractAddress = aave_pool)),
    error = function(e) NULL)
  if (is.null(resp) || is.null(resp$data)) return(0)
  d <- resp$data
  if (is.list(d) && !is.null(d$suppliedAmount)) return(as.numeric(d$suppliedAmount))
  as.numeric(d %||% 0)
}

# ── Approval ──────────────────────────────────────────────────────────────────

# Ensures the vault has approved `asset` for `platform` (e.g. "aavev3").
# Checks cache first; only hits the chain when the allowance is new/insufficient.
# force = TRUE bypasses cache and always calls /approve (used after a lend failure).
lending_ensure_approved <- function(network, vault, asset, platform, apiKey,
                                    force = FALSE) {
  if (!force && lending_is_approved(network, vault, asset, platform)) {
    cat(sprintf("  ℹ️  Approval already cached: %s on %s\n", asset, platform))
    return(invisible(TRUE))
  }
  cat(sprintf("  → Approving %s for %s on %s...\n", asset, platform, network))
  result <- tryCatch(
    # NOTE: /approve on port 8000 was renamed /approveRaw 2026-09-06 when the
    # public R-parity /approve wrapper was migrated to Express. Internal callers
    # keep using the raw route (no gateway validation needed on loopback).
    .lending_POST("approveRaw",
      params    = list(network  = network,
                       pool     = vault,
                       platform = platform,
                       apiKey   = apiKey),
      body_json = list(asset = asset)),
    error = function(e) list(status = "fail", message = e$message))

  if (!is.null(result$status) && result$status == "success") {
    lending_mark_approved(network, vault, asset, platform)
    cat(sprintf("  ✅ Approved %s for %s\n", asset, platform))
    Sys.sleep(15)   # wait for approval tx to mine before proceeding
    return(invisible(TRUE))
  }
  msg <- result$message %||% "unknown"
  cat(sprintf("  ❌ Approval failed: %s\n", msg))
  return(invisible(FALSE))
}

# ── Lend (deposit to Aave) ────────────────────────────────────────────────────

# Deposits `share`% of the vault's idle `token` balance into Aave V3.
# `token` is a symbol like "USDC" or "USDC.e" — address resolved internally.
# - Approves first (from cache or fresh)
# - If lend TX fails with an allowance error, forces a fresh approve and retries once
# - Verifies deposit with getSupplied after 30s
# - Sends email alert on failure or if tokens appear stuck
#
# Returns: TRUE on confirmed success, FALSE on failure.
lending_lend <- function(network, vault, token, apiKey,
                         share = 100, strategy_label = "") {
  asset     <- lending_resolve_asset(network, token)
  aave_pool <- lending_resolve_aave_pool(network)
  label <- if (nchar(strategy_label) > 0) sprintf("[%s] ", strategy_label) else ""

  idle <- lending_get_idle(network, vault, asset)
  cat(sprintf("  %sIdle balance: %.6f\n", label, idle))
  if (idle < LENDING_MIN_USD) {
    cat(sprintf("  %s⚠️  Balance too small (%.6f < %.2f) — skipping lend.\n",
                label, idle, LENDING_MIN_USD))
    return(invisible(FALSE))
  }

  # Ensure approval (from cache)
  if (!lending_ensure_approved(network, vault, asset, "aavev3", apiKey)) {
    .lending_alert(label, "Approval failed before lend",
                   sprintf("Vault: %s\nNetwork: %s\nAsset: %s", vault, network, asset))
    return(invisible(FALSE))
  }

  # Attempt lend
  cat(sprintf("  %s→ Lending %.0f%% (%s %.6f) to Aave V3...\n",
              label, share, network, idle))
  result <- .lending_try_lend(network, vault, asset, apiKey, share)

  # If failed: check error type before deciding how to handle
  if (is.null(result) || result$status != "success") {
    msg <- .lending_response_message(result)

    # Infrastructure/payment errors are not allowance problems. Do not spend gas re-approving.
    if (.lending_is_transient_or_payment_error(msg)) {
      cat(sprintf("  %s⚠️  Lend transient/payment error — will retry next cycle without re-approve.\n  Msg: %s\n",
                  label, msg))
      return(invisible(FALSE))
    }

    if (!.lending_is_allowance_error(msg)) {
      .lending_alert(label, "Lend failed",
                     sprintf("Vault: %s\nNetwork: %s\nMsg: %s",
                             vault, network, msg))
      return(invisible(FALSE))
    }

    # Confirmed allowance errors — force re-approve and retry once
    cat(sprintf("  %s⚠️  Lend failed (%s) — forcing re-approve and retrying...\n",
                label, msg))
    if (!lending_ensure_approved(network, vault, asset, "aavev3", apiKey, force = TRUE)) {
      .lending_alert(label, "Re-approve failed after lend failure",
                     sprintf("Vault: %s\nNetwork: %s\nMsg: %s",
                             vault, network, msg))
      return(invisible(FALSE))
    }
    result <- .lending_try_lend(network, vault, asset, apiKey, share)
    if (is.null(result) || result$status != "success") {
      .lending_alert(label, "Lend failed after re-approve",
                     sprintf("Vault: %s\nNetwork: %s\nMsg: %s",
                             vault, network, result$message %||% "unknown"))
      return(invisible(FALSE))
    }
  }

  cat(sprintf("  %s✅ Lend TX submitted: %s\n", label, result$msg %||% result$message))
  cat(sprintf("  %s⏳ Waiting 30s for confirmation...\n", label))
  Sys.sleep(30)

  # Verify
  supplied <- lending_get_supplied(network, vault, asset, aave_pool)
  if (supplied >= LENDING_MIN_USD) {
    cat(sprintf("  %s✅ Lend confirmed — %.6f on Aave.\n", label, supplied))
    return(invisible(TRUE))
  }

  # Not confirmed — check if idle dropped (tx may still be indexing)
  idle_after <- lending_get_idle(network, vault, asset)
  if (idle_after < idle * 0.5) {
    cat(sprintf("  %s⚠️  Lend TX mined but getSupplied still indexing. Idle: %.6f → %.6f\n",
                label, idle, idle_after))
    return(invisible(TRUE))
  }

  .lending_alert(label, "Lend unconfirmed after 30s",
                 sprintf("Vault: %s\nNetwork: %s\nTX: %s\nIdle before: %.6f\nIdle after: %.6f\nSupplied: %.6f",
                         vault, network, result$msg %||% "?", idle, idle_after, supplied))
  return(invisible(FALSE))
}

# ── Unlend (withdraw from Aave) ───────────────────────────────────────────────

# Withdraws `share`% of the vault's supplied Aave balance back to idle.
# `token` is a symbol like "USDC" or "USDC.e" — address resolved internally.
# - Does not approve first: Aave withdraw does not consume token allowance
# - Does not force re-approve after failures; approvals are one-time setup
# - Verifies withdrawal with getSupplied after 30s
# - Sends email alert on failure or if tokens remain stuck on Aave
#
# Returns: TRUE on confirmed success, FALSE on failure.
lending_unlend <- function(network, vault, token, apiKey,
                           share = 100, strategy_label = "") {
  asset     <- lending_resolve_asset(network, token)
  aave_pool <- lending_resolve_aave_pool(network)
  label <- if (nchar(strategy_label) > 0) sprintf("[%s] ", strategy_label) else ""

  supplied <- lending_get_supplied(network, vault, asset, aave_pool)
  cat(sprintf("  %sSupplied on Aave: %.6f\n", label, supplied))
  if (supplied < LENDING_MIN_USD) {
    cat(sprintf("  %s⚠️  Nothing significant on Aave (%.6f) — skipping unlend.\n",
                label, supplied))
    return(invisible(FALSE))
  }

  # Attempt unlend
  cat(sprintf("  %s→ Unlending %.0f%% (%.6f) from Aave V3...\n",
              label, share, supplied))
  result <- .lending_try_unlend(network, vault, asset, aave_pool, apiKey, share)

  # If failed: surface the real failure. Re-approving would waste gas on gas/payment/RPC errors.
  if (is.null(result) || result$status != "success") {
    msg <- .lending_response_message(result)
    cat(sprintf("  %s⚠️  Unlend failed (%s) — not re-approving.\n", label, msg))
    .lending_alert(label, "Unlend failed",
                   sprintf("Vault: %s\nNetwork: %s\nMsg: %s",
                           vault, network, msg))
    return(invisible(FALSE))
  }

  cat(sprintf("  %s✅ Unlend TX submitted: %s\n", label, result$msg %||% result$message))
  cat(sprintf("  %s⏳ Waiting 30s for confirmation...\n", label))
  Sys.sleep(30)

  # Verify
  supplied_after <- lending_get_supplied(network, vault, asset, aave_pool)
  if (supplied_after < LENDING_MIN_USD) {
    cat(sprintf("  %s✅ Unlend confirmed — USDC back in vault.\n", label))
    return(invisible(TRUE))
  }

  .lending_alert(label, sprintf("USDC stuck on Aave after unlend (%.6f remaining)", supplied_after),
                 sprintf("Vault: %s\nNetwork: %s\nTX: %s\nBefore: %.6f\nAfter: %.6f",
                         vault, network, result$msg %||% "?", supplied, supplied_after))
  return(invisible(FALSE))
}

# ── Internal TX senders ───────────────────────────────────────────────────────

.lending_try_lend <- function(network, vault, asset, apiKey, share) {
  tryCatch(
    .lending_POST("lend", list(network  = network,
                               pool     = vault,
                               asset    = asset,
                               platform = "aavev3",
                               share    = share,
                               apiKey   = apiKey)),
    error = function(e) list(status = "fail", message = e$message))
}

.lending_try_unlend <- function(network, vault, asset, aave_pool, apiKey, share) {
  tryCatch(
    .lending_POST("unlend", list(network         = network,
                                 pool            = vault,
                                 asset           = asset,
                                 platform        = "aavev3",
                                 share           = share,
                                 contractAddress = aave_pool,
                                 apiKey          = apiKey)),
    error = function(e) list(status = "fail", message = e$message))
}

# ── Alert helper ──────────────────────────────────────────────────────────────

# alert_state per strategy: new.env with $count + $date (see email_alerts.R)
.lending_alert_state <- new.env(parent = emptyenv())
.lending_alert_state$count <- 0L
.lending_alert_state$date  <- Sys.Date()

.lending_alert <- function(label, subject_suffix, body_text) {
  full_subject <- sprintf("⚠️ Aave Lending Alert %s— %s", label, subject_suffix)
  cat(sprintf("  ❌ ALERT: %s\n", full_subject))
  cat(sprintf("     %s\n", gsub("\n", "\n     ", body_text)))
  if (exists("can_send_alert") && can_send_alert(.lending_alert_state)) {
    html <- sprintf(
      "<h3>%s</h3><pre>%s</pre><p>Time: %s</p>",
      full_subject,
      body_text,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")
    )
    send_resend_email(full_subject, html)
    .lending_alert_state$count <- .lending_alert_state$count + 1L
  }
}
