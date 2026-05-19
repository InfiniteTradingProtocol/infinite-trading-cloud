# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# === Strategy Configurations ===
networks        = c("base")
protocols       = c("dhedge")
pools           = c("")                  # ← paste vault address here before deploying
pairs           = c("MORPHO-USDC")
candles_pairs   = c("MORPHO-USD")
timeframes      = c("6h")
slippages       = c(0.5)
shares          = c(100)
platforms       = c("odos")
max_usds        = c(5000)
thresholds      = c(1)

# === Strategy Parameters (v2 — tuned) ===
ema_fast        = c(9, 10, 11, 12, 13)   # 5×5 EMA grid = 25 combos
ema_slow        = c(29, 30, 31, 32, 33)
long_threshold  = 0.60    # >= 60% of combos bullish to enter
sma_period      = 50      # trend filter: only long above SMA(50)
rsi_period      = 14
rsi_min         = 45      # don't enter when RSI < 45

# Trailing stop + re-entry
trailing_stop   = 0.08    # exit if price drops 8% from rolling peak
reentry_pct     = 0.05    # re-entry allowed after 5% recovery above stop-out price
cooldown_bars   = 3       # minimum candle bars to wait after stop before re-entry

# === State Variables (per strategy) ===
n_strategies  <- length(pairs)
last_sides    <- rep("neutral", n_strategies)

# Stop tracking state per strategy
in_position   <- rep(FALSE, n_strategies)
peak_price    <- rep(NA_real_, n_strategies)
stopped_out   <- rep(FALSE, n_strategies)
stop_price    <- rep(NA_real_, n_strategies)
stop_bar      <- rep(NA_integer_, n_strategies)
bar_counter   <- rep(0L, n_strategies)

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("\n[", Sys.time(), "] Running strategy ", i, ": ", pairs[i], "\n"))

      candles <- get_candles_with_retry(
        pair       = candles_pairs[i],
        numcandles = 300,
        timeframe  = timeframes[i]
      )

      close <- as.numeric(Cl(candles))
      n_bars <- length(close)
      bar_counter[i] <- bar_counter[i] + 1L

      # ── EMA grid signal ──────────────────────────────────
      n_combos <- length(ema_fast) * length(ema_slow)
      votes    <- 0
      for (f in ema_fast) {
        for (s in ema_slow) {
          ef    <- EMA(close, n = f)
          es    <- EMA(close, n = s)
          votes <- votes + ifelse(!is.na(last(ef)) & !is.na(last(es)) & last(ef) > last(es), 1, 0)
        }
      }
      probability <- votes / n_combos

      # ── Trend & momentum filters ─────────────────────────
      sma_vals <- SMA(close, n = sma_period)
      rsi_vals <- RSI(close, n = rsi_period)

      above_sma  <- !is.na(last(sma_vals)) && last(close) > last(sma_vals)
      rsi_ok     <- !is.na(last(rsi_vals)) && last(rsi_vals) > rsi_min
      ema_signal <- probability >= long_threshold

      raw_signal <- if (ema_signal && above_sma && rsi_ok) "long" else "neutral"

      cat(sprintf("  EMA prob: %.0f%%  |  above SMA50: %s  |  RSI: %.1f  |  raw signal: %s\n",
                  probability * 100,
                  ifelse(above_sma, "YES", "NO"),
                  ifelse(!is.na(last(rsi_vals)), last(rsi_vals), NA),
                  raw_signal))

      # ── Trailing stop check ──────────────────────────────
      current_price <- last(close)

      # Check re-entry cooldown expiry
      if (stopped_out[i]) {
        bars_since_stop <- bar_counter[i] - stop_bar[i]
        price_recovered <- !is.na(stop_price[i]) && current_price >= stop_price[i] * (1 + reentry_pct)
        cooldown_done   <- bars_since_stop >= cooldown_bars

        if (cooldown_done && price_recovered) {
          cat(sprintf("  ✅ Re-entry unlocked (recovered %.1f%% above stop, %d bars elapsed)\n",
                      reentry_pct * 100, bars_since_stop))
          stopped_out[i] <- FALSE
          stop_price[i]  <- NA_real_
          stop_bar[i]    <- NA_integer_
        } else {
          cat(sprintf("  ⏳ In cooldown: %d/%d bars  |  price recovery: %s\n",
                      bars_since_stop, cooldown_bars,
                      ifelse(price_recovered, "YES", "NO")))
        }
      }

      # Determine effective side
      if (in_position[i]) {
        # Update trailing peak
        if (!is.na(current_price) && (is.na(peak_price[i]) || current_price > peak_price[i])) {
          peak_price[i] <- current_price
        }

        # Trailing stop triggered?
        if (!is.na(peak_price[i]) && current_price < peak_price[i] * (1 - trailing_stop)) {
          cat(sprintf("  🛑 Trailing stop hit! Peak: %.4f  Current: %.4f  Drop: %.1f%%\n",
                      peak_price[i], current_price,
                      (1 - current_price / peak_price[i]) * 100))
          effective_side <- "neutral"
          in_position[i] <- FALSE
          stopped_out[i] <- TRUE
          stop_price[i]  <- current_price
          stop_bar[i]    <- bar_counter[i]
          peak_price[i]  <- NA_real_

        } else if (raw_signal == "neutral") {
          # Clean signal exit
          effective_side <- "neutral"
          in_position[i] <- FALSE
          peak_price[i]  <- NA_real_

        } else {
          effective_side <- "long"
        }

      } else {
        # Not in position — can we enter?
        if (raw_signal == "long" && !stopped_out[i]) {
          effective_side <- "long"
          in_position[i] <- TRUE
          peak_price[i]  <- current_price
        } else {
          effective_side <- "neutral"
        }
      }

      cat(sprintf("  📊 Effective side: %s  |  In position: %s  |  Stopped out: %s\n",
                  effective_side,
                  ifelse(in_position[i], "YES", "NO"),
                  ifelse(stopped_out[i], "YES", "NO")))

      # ── Execute if side changed ───────────────────────────
      if (last_sides[i] != effective_side) {
        cat(sprintf("  🔄 Side change: %s → %s — sending setBot\n",
                    last_sides[i], effective_side))
        last_sides[i] <- effective_side

        itp_api(endpoint = "setBot", params = list(
          apiKey    = apiKey,
          protocol  = protocols[i],
          network   = networks[i],
          pool      = pools[i],
          pair      = pairs[i],
          side      = effective_side,
          max_usd   = max_usds[i],
          slippage  = slippages[i],
          threshold = thresholds[i],
          share     = shares[i],
          platform  = platforms[i]
        ))
      } else {
        cat(sprintf("  ✓ Side unchanged: %s — no action\n", effective_side))
      }

    }, error = function(e) {
      cat(paste0("  ❌ Error in strategy ", i, ": ", e$message, "\n"))
    })
  }

  cat(paste0("\n[", Sys.time(), "] Cycle complete. Sleeping 6h...\n"))
  Sys.sleep(60 * 60 * 6)   # 6H candles → check every 6H
}
