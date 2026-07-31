# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
source("~/infinitetrading/src/utils/email_alerts.R")
source("~/infinitetrading/src/utils/lending.R")
library(TTR)
library(quantmod)

# === Strategy Configurations (Index-matched) ===
networks        = c("base", "optimism", "base", "polygon")
protocols       = c("dhedge",   "dhedge",  "dhedge", "dhedge")
pools           = c("0x03d1a73d66556f0d7ad0e1f57043e866a7c08d6d", "0x6a18000ebd71b79d345f9f9753253ae4fff84e27", "0x0ae4be81cdbbd7a0a0e86ceb8ef9201837ae41b4", "0x269782b044b2229a596439c4d8ec99baf32e4c60")
pairs           = c("wstETH-USDC", "WBTC-USDC", "MORPHO-USDC", "LINK-USDC")
candles_pairs   = c("ETH-USD", "BTC-USD", "MORPHO-USD", "LINK-USD")
timeframes      = c("1d","1d","6h","6h")
slippages       = c(0.5, 0.5, 0.5, 2.5)
shares          = c(100, 100, 100, 100)
platforms       = c("odos", "odos", "odos", "kyberswap")
max_usds        = c(5000, 5000, 5000, 5000)
thresholds      = c(1, 1, 1, 1)

# === Strategy Parameters ===
atr_periods     = c(100, 100, 100, 100)
atr_multipliers = c(5, 5, 5, 5)
sma_lens        = c(50, 50, 50, 50)

# === Aave lending config ===
# Token symbol only — lending.R resolves contract address and Aave pool internally.
# Set NA to disable Aave for a strategy.
lending_tokens  = c("USDC", "USDC", "USDC", "USDC")

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)
in_uptrends     <- rep(FALSE, n_strategies)

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("Running strategy ", i, ": ", pairs[i], "\n"))
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles); high <- Hi(candles); low <- Lo(candles)

      atr_vals <- ATR(HLC(candles), n = atr_periods[i])[,2]
      hl2 <- (high + low) / 2
      upperBand <- hl2 + atr_multipliers[i] * atr_vals
      lowerBand <- hl2 - atr_multipliers[i] * atr_vals

      superTrend <- rep(NA, length(close))
      trendUp <- rep(TRUE, length(close))

      for (j in 2:length(close)) {
        prevST <- ifelse(!is.na(superTrend[j - 1]), superTrend[j - 1], lowerBand[j - 1])
        trendUp[j] <- ifelse(close[j] > prevST, TRUE,
                          ifelse(close[j] < prevST, FALSE, trendUp[j - 1]))
        superTrend[j] <- ifelse(trendUp[j], max(lowerBand[j], prevST), min(upperBand[j], prevST))
      }

      # SMA + Trend Filter
      sma <- SMA(close, n = sma_lens[i])
      isUptrend <- (close > sma)
      uptrendCount <- lag(isUptrend, 0) + lag(isUptrend, 1)
      isUpConfirmed <- uptrendCount == 2
      isDownConfirmed <- (lag(close, 0) < sma & lag(close, 1) < sma)

      newUptrend <- isUpConfirmed & !in_uptrends[i]
      in_uptrends[i] <- ifelse(isUpConfirmed[length(isUpConfirmed)], TRUE,
                             ifelse(isDownConfirmed[length(isDownConfirmed)], FALSE, in_uptrends[i]))

      enterOnNewUptrend <- last(newUptrend, na.rm = TRUE)
      enterOnSuperTrend <- last(close > superTrend & lag(close) <= lag(superTrend) & in_uptrends[i], na.rm = TRUE)
      exitOnSuperTrend  <- last(close < superTrend & lag(close) >= lag(superTrend), na.rm = TRUE)
      exitOnDowntrend   <- last(isDownConfirmed, na.rm = TRUE)

      is_long_signal <- isTRUE(enterOnNewUptrend) || isTRUE(enterOnSuperTrend)
      is_exit_signal <- isTRUE(exitOnSuperTrend)  || isTRUE(exitOnDowntrend)
      has_aave       <- !is.na(lending_tokens[i])

      # ── LONG signal ──────────────────────────────────────────────────────────
      if (is_long_signal) {
        cat(paste0("→ Strategy ", i, " - LONG signal\n"))

        # Pull USDC off Aave first so the bot has funds to trade
        if (has_aave) {
          lending_unlend(network        = networks[i],
                         vault         = pools[i],
                         token         = lending_tokens[i],
                         apiKey        = apiKey,
                         strategy_label = pairs[i])
        }

        if (last_sides[i] != "long") {
          last_sides[i] <- "long"
          itp_api(endpoint = "setBot", params = list(
            apiKey    = apiKey, protocol  = protocols[i],
            network   = networks[i], pool      = pools[i],
            pair      = pairs[i], side      = "long",
            max_usd   = max_usds[i], slippage  = slippages[i],
            threshold = thresholds[i], share     = shares[i],
            platform  = platforms[i]
          ))
        }

      # ── EXIT / NEUTRAL signal ─────────────────────────────────────────────
      } else if (is_exit_signal) {
        cat(paste0("→ Strategy ", i, " - EXIT signal\n"))

        if (last_sides[i] != "neutral") {
          last_sides[i] <- "neutral"
          itp_api(endpoint = "setBot", params = list(
            apiKey    = apiKey, protocol  = protocols[i],
            network   = networks[i], pool      = pools[i],
            pair      = pairs[i], side      = "neutral",
            max_usd   = max_usds[i], slippage  = slippages[i],
            threshold = thresholds[i], share     = shares[i],
            platform  = platforms[i]
          ))
        }

        # Deposit idle USDC to Aave once the trade has settled
        if (has_aave) {
          lending_lend(network        = networks[i],
                       vault         = pools[i],
                       token         = lending_tokens[i],
                       apiKey        = apiKey,
                       strategy_label = pairs[i])
        }

      # ── Already neutral: sweep any idle USDC to Aave ──────────────────────
      } else if (has_aave && last_sides[i] == "neutral") {
        lending_lend(network        = networks[i],
                     vault         = pools[i],
                     token         = lending_tokens[i],
                     apiKey        = apiKey,
                     strategy_label = pairs[i])
      }

    }, error = function(e) {
      cat(paste0("Error in strategy ", i, ": ", e$message, "\n"))
    })
  }

  Sys.sleep(60*60*6)  # Sleep 6 hours before next cycle
}


# === Strategy Configurations (Index-matched) ===
networks        = c("base", "optimism", "base", "polygon")
protocols       = c("dhedge",   "dhedge",  "dhedge", "dhedge")
pools           = c("0x03d1a73d66556f0d7ad0e1f57043e866a7c08d6d", "0x6a18000ebd71b79d345f9f9753253ae4fff84e27", "0x0ae4be81cdbbd7a0a0e86ceb8ef9201837ae41b4", "0x269782b044b2229a596439c4d8ec99baf32e4c60")
pairs           = c("wstETH-USDC", "WBTC-USDC", "MORPHO-USDC", "LINK-USDC")
candles_pairs   = c("ETH-USD", "BTC-USD", "MORPHO-USD", "LINK-USD")
timeframes      = c("1d","1d","6h","6h")
slippages       = c(0.5, 0.5, 0.5, 2.5)
shares          = c(100, 100, 100, 100)
platforms       = c("odos", "odos", "odos", "kyberswap")
max_usds        = c(5000, 5000, 5000, 5000)
thresholds      = c(1, 1, 1, 1)
# === Strategy Parameters ===
atr_periods     = c(100, 100, 100, 100)
atr_multipliers = c(5, 5, 5, 5)
sma_lens        = c(50, 50, 50, 50)

# === Aave V3 config (index-matched to pools/networks) ===
# USDC contract per network
usdc_addrs = c(
  "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",   # base
  "0x0b2c639c533813f4aa9d7837caf62653d097ff85",   # optimism
  "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",   # base
  "0x3c499c542cef5e3811e1192ce70d8cc03d5c3359"    # polygon
)
# Aave V3 pool contract per network
aave_pool_addrs = c(
  "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",   # base
  "0x794a61358d6845594f94dc1db02a252b5b4814ad",   # optimism
  "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",   # base
  "0x794a61358d6845594f94dc1db02a252b5b4814ad"    # polygon
)
MIN_USDC_USD <- 1.0   # ignore dust below $1

# === Alert state (max 2 Aave-failure emails per day) ===
aave_alert        <- new.env(parent = emptyenv())
aave_alert$count  <- 0L
aave_alert$date   <- Sys.Date()

# === API helpers ===
local_POST <- function(endpoint, params) {
  url  <- paste0("http://localhost:8000/", endpoint)
  resp <- POST(url, query = params, body = "", encode = "raw")
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

local_GET <- function(endpoint, params) {
  url  <- paste0("http://localhost:8000/", endpoint)
  resp <- GET(url, query = params)
  fromJSON(content(resp, "text", encoding = "UTF-8"))
}

# === Aave helpers ===

get_idle_usdc <- function(network, pool, usdc_addr) {
  resp <- tryCatch(local_GET("getTokenBalance", list(
    network = network, wallet = pool, asset = usdc_addr
  )), error = function(e) NULL)
  if (is.null(resp) || is.null(resp$data)) return(0)
  as.numeric(resp$data$balance)
}

get_aave_supplied <- function(network, pool, usdc_addr, aave_pool) {
  resp <- tryCatch(local_GET("getSupplied", list(
    network         = network,
    pool            = pool,
    asset           = usdc_addr,
    contractAddress = aave_pool
  )), error = function(e) NULL)
  if (is.null(resp) || is.null(resp$data)) return(0)
  as.numeric(resp$data)
}

# Deposit all idle USDC to Aave V3. No-op if vault has < MIN_USDC_USD idle.
deposit_usdc_to_aave <- function(i) {
  network   <- networks[i];   pool      <- pools[i]
  usdc_addr <- usdc_addrs[i]; aave_pool <- aave_pool_addrs[i]
  label     <- pairs[i]

  idle <- get_idle_usdc(network, pool, usdc_addr)
  if (idle < MIN_USDC_USD) {
    cat(sprintf("  [%s] No idle USDC to deposit (%.4f USD)\n", label, idle))
    return(invisible(FALSE))
  }

  cat(sprintf("  → [%s] Depositing $%.4f USDC to Aave\n", label, idle))
  result <- tryCatch(local_POST("lend", list(
    network  = network, pool     = pool,
    asset    = usdc_addr, platform = "aavev3",
    share    = 100, apiKey   = apiKey
  )), error = function(e) list(status = "fail", message = e$message))

  ok <- isTRUE(result$status == "success")
  if (!ok) {
    err <- result$message %||% "unknown error"
    cat(sprintf("  ⚠  [%s] Aave deposit failed: %s\n", label, err))
    if (can_send_alert(aave_alert)) {
      send_resend_email(
        subject   = sprintf("[SuperTrend] Aave Deposit Failed: %s", label),
        html_body = sprintf(paste0(
          "<h2>&#9888; Aave USDC Deposit Failed</h2>",
          "<p><strong>Strategy:</strong> SuperTrend</p>",
          "<p><strong>Pair:</strong> %s | <strong>Network:</strong> %s</p>",
          "<p><strong>Vault:</strong> %s</p>",
          "<p><strong>Amount:</strong> $%.4f USDC</p>",
          "<p><strong>Error:</strong> <span style='color:red'>%s</span></p>",
          "<p>This may indicate low gas or an Aave issue. Check the vault manually.</p>",
          "<p><em>%s UTC</em></p>"
        ), label, network, pool, idle, err, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      )
      aave_alert$count <- aave_alert$count + 1L
    }
    return(invisible(FALSE))
  }

  cat(sprintf("  ✅ [%s] Aave deposit submitted — waiting 30s to confirm\n", label))
  Sys.sleep(30)

  supplied <- get_aave_supplied(network, pool, usdc_addr, aave_pool)
  if (supplied >= MIN_USDC_USD) {
    cat(sprintf("  ✅ [%s] Confirmed: $%.4f USDC on Aave\n", label, supplied))
  } else {
    cat(sprintf("  ⚠  [%s] Post-deposit check: only $%.4f on Aave — may be stuck\n", label, supplied))
    if (can_send_alert(aave_alert)) {
      send_resend_email(
        subject   = sprintf("[SuperTrend] Aave Deposit Unconfirmed: %s", label),
        html_body = sprintf(paste0(
          "<h2>&#9888; Aave USDC Deposit Unconfirmed After 30s</h2>",
          "<p><strong>Strategy:</strong> SuperTrend</p>",
          "<p><strong>Pair:</strong> %s | <strong>Network:</strong> %s</p>",
          "<p><strong>Vault:</strong> %s</p>",
          "<p><strong>Expected:</strong> $%.4f | <strong>On Aave:</strong> $%.4f</p>",
          "<p>The deposit may be stuck. Check the vault manually.</p>",
          "<p><em>%s UTC</em></p>"
        ), label, network, pool, idle, supplied, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      )
      aave_alert$count <- aave_alert$count + 1L
    }
  }
  return(invisible(ok))
}

# Withdraw all USDC from Aave V3. No-op if nothing is on Aave.
withdraw_usdc_from_aave <- function(i) {
  network   <- networks[i];   pool      <- pools[i]
  usdc_addr <- usdc_addrs[i]; aave_pool <- aave_pool_addrs[i]
  label     <- pairs[i]

  supplied <- get_aave_supplied(network, pool, usdc_addr, aave_pool)
  if (supplied < MIN_USDC_USD) {
    cat(sprintf("  [%s] No USDC on Aave to withdraw (%.4f USD)\n", label, supplied))
    return(invisible(FALSE))
  }

  cat(sprintf("  → [%s] Withdrawing $%.4f USDC from Aave\n", label, supplied))
  result <- tryCatch(local_POST("unlend", list(
    network         = network, pool            = pool,
    asset           = usdc_addr, platform        = "aavev3",
    share           = 100, contractAddress = aave_pool,
    apiKey          = apiKey
  )), error = function(e) list(status = "fail", message = e$message))

  ok <- isTRUE(result$status == "success")
  if (!ok) {
    err <- result$message %||% "unknown error"
    cat(sprintf("  ⚠  [%s] Aave withdraw failed: %s\n", label, err))
    if (can_send_alert(aave_alert)) {
      send_resend_email(
        subject   = sprintf("[SuperTrend] Aave Withdraw Failed: %s — BOT BLOCKED", label),
        html_body = sprintf(paste0(
          "<h2>&#128680; Aave USDC Withdraw Failed — LONG Trade Blocked</h2>",
          "<p><strong>Strategy:</strong> SuperTrend</p>",
          "<p><strong>Pair:</strong> %s | <strong>Network:</strong> %s</p>",
          "<p><strong>Vault:</strong> %s</p>",
          "<p><strong>Aave Balance:</strong> $%.4f USDC</p>",
          "<p><strong>Error:</strong> <span style='color:red'>%s</span></p>",
          "<p>USDC is stuck on Aave. The bot CANNOT execute the LONG trade until this is resolved.</p>",
          "<p><em>%s UTC</em></p>"
        ), label, network, pool, supplied, err, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      )
      aave_alert$count <- aave_alert$count + 1L
    }
    return(invisible(FALSE))
  }

  cat(sprintf("  ✅ [%s] Aave withdraw submitted — waiting 30s to confirm\n", label))
  Sys.sleep(30)

  still_on_aave <- get_aave_supplied(network, pool, usdc_addr, aave_pool)
  if (still_on_aave < MIN_USDC_USD) {
    cat(sprintf("  ✅ [%s] Confirmed: USDC fully withdrawn from Aave\n", label))
  } else {
    cat(sprintf("  ⚠  [%s] Post-withdraw check: still $%.4f on Aave — tokens may be stuck\n", label, still_on_aave))
    if (can_send_alert(aave_alert)) {
      send_resend_email(
        subject   = sprintf("[SuperTrend] USDC Stuck on Aave: %s — URGENT", label),
        html_body = sprintf(paste0(
          "<h2>&#128680; USDC Still on Aave After Withdraw</h2>",
          "<p><strong>Strategy:</strong> SuperTrend — LONG signal is <strong>BLOCKED</strong></p>",
          "<p><strong>Pair:</strong> %s | <strong>Network:</strong> %s</p>",
          "<p><strong>Vault:</strong> %s</p>",
          "<p><strong>Still on Aave:</strong> $%.4f USDC</p>",
          "<p>The bot cannot execute the LONG trade until USDC is available. Manual intervention required.</p>",
          "<p><em>%s UTC</em></p>"
        ), label, network, pool, still_on_aave, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      )
      aave_alert$count <- aave_alert$count + 1L
    }
  }
  return(invisible(ok))
}

# === State Variables (per strategy) ===
n_strategies    <- length(pairs)
last_sides      <- rep("hold", n_strategies)
in_uptrends     <- rep(FALSE, n_strategies)

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("Running strategy ", i, ": ", pairs[i], "\n"))
      candles <- get_candles_with_retry(pair = candles_pairs[i], numcandles = 300, timeframe = timeframes[i])
      close <- Cl(candles); high <- Hi(candles); low <- Lo(candles)

      # SuperTrend Calculation
      #ATR_OBJECT =  ATR(HLC(candles), n = atr_periods[i])
      #print(head(ATR_OBJECT,2))

      atr_vals <- ATR(HLC(candles), n = atr_periods[i])[,2]
      hl2 <- (high + low) / 2
      upperBand <- hl2 + atr_multipliers[i] * atr_vals
      lowerBand <- hl2 - atr_multipliers[i] * atr_vals

      superTrend <- rep(NA, length(close))
      trendUp <- rep(TRUE, length(close))

      for (j in 2:length(close)) {
        prevST <- ifelse(!is.na(superTrend[j - 1]), superTrend[j - 1], lowerBand[j - 1])
        trendUp[j] <- ifelse(close[j] > prevST, TRUE,
                          ifelse(close[j] < prevST, FALSE, trendUp[j - 1]))
        superTrend[j] <- ifelse(trendUp[j], max(lowerBand[j], prevST), min(upperBand[j], prevST))
      }

      # SMA + Trend Filter
      sma <- SMA(close, n = sma_lens[i])
      isUptrend <- (close > sma)
      uptrendCount <- lag(isUptrend, 0) + lag(isUptrend, 1)
      isUpConfirmed <- uptrendCount == 2
      isDownConfirmed <- (lag(close, 0) < sma & lag(close, 1) < sma)

      newUptrend <- isUpConfirmed & !in_uptrends[i]
      in_uptrends[i] <- ifelse(isUpConfirmed[length(isUpConfirmed)], TRUE,
                             ifelse(isDownConfirmed[length(isDownConfirmed)], FALSE, in_uptrends[i]))

      # Trade Signals
      enterOnNewUptrend <- last(newUptrend, na.rm = TRUE)
      enterOnSuperTrend <- last(close > superTrend & lag(close) <= lag(superTrend) & in_uptrends[i], na.rm = TRUE)
      exitOnSuperTrend <- last(close < superTrend & lag(close) >= lag(superTrend), na.rm = TRUE)
      exitOnDowntrend <- last(isDownConfirmed, na.rm = TRUE)

      is_long_signal <- isTRUE(enterOnNewUptrend) || isTRUE(enterOnSuperTrend)
      is_exit_signal <- isTRUE(exitOnSuperTrend)  || isTRUE(exitOnDowntrend)

      # Trade Execution
      if (is_long_signal) {
        cat(paste0("→ Strategy ", i, " - LONG signal\n"))
        # Withdraw USDC from Aave first so the bot has funds to buy
        withdraw_usdc_from_aave(i)
        if (last_sides[i] != "long") {
          last_sides[i] <- "long"
          itp_api(endpoint = "setBot", params = list(
            apiKey    = apiKey,
            protocol  = protocols[i],
            network   = networks[i],
            pool      = pools[i],
            pair      = pairs[i],
            side      = "long",
            max_usd   = max_usds[i],
            slippage  = slippages[i],
            threshold = thresholds[i],
            share     = shares[i],
            platform  = platforms[i]
          ))
        }
      } else if (is_exit_signal) {
        cat(paste0("→ Strategy ", i, " - EXIT signal\n"))
        if (last_sides[i] != "neutral") {
          last_sides[i] <- "neutral"
          itp_api(endpoint = "setBot", params = list(
            apiKey    = apiKey,
            protocol  = protocols[i],
            network   = networks[i],
            pool      = pools[i],
            pair      = pairs[i],
            side      = "neutral",
            max_usd   = max_usds[i],
            slippage  = slippages[i],
            threshold = thresholds[i],
            share     = shares[i],
            platform  = platforms[i]
          ))
        }
        # Deposit any idle USDC to Aave. Then sweep a few more times with short
        # delays to catch USDC arriving from subsequent sell chunks (tradebot
        # may execute sells in multiple max_usd-sized transactions).
        for (sweep in 1:4) {
          deposit_usdc_to_aave(i)
          if (sweep < 4) Sys.sleep(60 * 2)  # 2 min between sweeps (6 min total)
        }
      }

      # When holding neutral (no new signal), still try to deposit any idle USDC
      # that may have arrived from a previous trade settling.
      if (!is_long_signal && !is_exit_signal && last_sides[i] == "neutral") {
        deposit_usdc_to_aave(i)
      }
    }, error = function(e) {
      cat(paste0("Error in strategy ", i, ": ", e$message, "\n"))
    })
  }

  Sys.sleep(60*60*6)  # Sleep 6 hours before next cycle
}

