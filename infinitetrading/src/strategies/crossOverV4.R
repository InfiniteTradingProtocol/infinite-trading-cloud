# === Dependencies ===
source("~/infinitetrading/src/strategies/main.R")
library(TTR)
library(quantmod)

# =============================================================
# crossOverV4 — Dual-Mode: Trend + Accumulation
#
# TREND MODE (same as v2):
#   • 25-combo EMA grid (fast 9-13, slow 29-33), >= 60% bullish
#   • Close > SMA(50) trend filter
#   • RSI(14) > 45 momentum guard
#   • 8% trailing stop, 3-bar cooldown after stop-out
#
# ACCUMULATION MODE (new — never sidelined too long):
#   • Price >= 35% below its 180-candle rolling high   (deep dip)
#   • RSI(14) < 35                                     (oversold)
#   • Price >= 10% above its 90-candle rolling low     (bounced, not knife)
#   • 15% trailing stop (wider — volatile bottoms)
#   • Exits when trend mode fires (hands off cleanly)
#     or 15% trailing stop is hit
#
# Pairs:   cbBTC-USDC (BTC), cbETH-USDC (ETH) on Base
# Candles: BTC-USD, ETH-USD  (6h, 300 bars)
# =============================================================

# === Strategy Configurations ===
networks        = c("base",         "base")
protocols       = c("dhedge",       "dhedge")
pools           = c("0xbb707e4969d7e9288aa1d96273f1afd61e48e908", "0x0922956f34111cce8348f457cc0f7d51540aa6c5")
pairs           = c("cbBTC-USDC",   "cbETH-USDC")
candles_pairs   = c("BTC-USD",      "ETH-USD")
timeframes      = c("6h",           "6h")
slippages       = c(0.5,            0.5)
shares          = c(100,            100)
platforms       = c("odos",         "odos")
max_usds        = c(5000,           5000)
thresholds      = c(1,              1)

# === Trend Mode Parameters ===
ema_fast        = c(9, 10, 11, 12, 13)
ema_slow        = c(29, 30, 31, 32, 33)
long_threshold  = 0.60
sma_period      = 50
rsi_period      = 14
rsi_min         = 45
trailing_stop_trend = 0.08
reentry_pct     = 0.05
cooldown_bars   = 3

# === Accumulation Mode Parameters ===
accum_drawdown_pct  = 0.35    # price must be >= 35% below rolling high
accum_high_bars     = 180     # rolling window for "how far from peak" (180 × 6h = 45 days)
accum_rsi_max       = 35      # RSI(14) must be < 35 (oversold)
accum_bounce_pct    = 0.10    # price must be >= 10% above rolling low (no falling knife)
accum_low_bars      = 90      # rolling window for bounce confirmation (90 × 6h ≈ 22 days)
trailing_stop_accum = 0.15    # wider trailing stop for accumulation entries

# === State Persistence ===
STATE_FILE <- "~/infinitetrading/src/strategies/crossOverV4_state.rds"

save_state <- function() {
  state <- list(
    last_sides  = last_sides,
    in_position = in_position,
    mode        = mode,
    peak_price  = peak_price,
    stopped_out = stopped_out,
    stop_price  = stop_price,
    stop_bar    = stop_bar,
    bar_counter = bar_counter,
    saved_at    = Sys.time()
  )
  saveRDS(state, STATE_FILE)
  cat(sprintf("  💾 State saved → %s\n", STATE_FILE))
}

load_state <- function() {
  if (file.exists(STATE_FILE)) {
    state <- readRDS(STATE_FILE)
    # Only restore if state matches current number of strategies
    if (length(state$in_position) == n_strategies) {
      last_sides  <<- state$last_sides
      in_position <<- state$in_position
      mode        <<- state$mode
      peak_price  <<- state$peak_price
      stopped_out <<- state$stopped_out
      stop_price  <<- state$stop_price
      stop_bar    <<- state$stop_bar
      bar_counter <<- state$bar_counter
      cat(sprintf("  ✅ State restored from %s (saved %s)\n", STATE_FILE, format(state$saved_at, "%Y-%m-%d %H:%M:%S")))
      for (i in seq_len(n_strategies)) {
        cat(sprintf("     Strategy %d (%s): in_pos=%s mode=%s peak=%.2f stopped=%s\n",
                    i, pairs[i],
                    ifelse(in_position[i], "YES", "NO"),
                    ifelse(is.na(mode[i]), "—", mode[i]),
                    ifelse(is.na(peak_price[i]), 0, peak_price[i]),
                    ifelse(stopped_out[i], "YES", "NO")))
      }
    } else {
      cat(sprintf("  ⚠️  State file has %d strategies, expected %d — ignoring\n",
                  length(state$in_position), n_strategies))
    }
  } else {
    cat("  ℹ️  No state file found — starting fresh\n")
  }
}

# === Per-Strategy State ===
n_strategies <- length(pairs)
last_sides   <- rep("neutral", n_strategies)

# Trend mode state
in_position  <- rep(FALSE,      n_strategies)
mode         <- rep(NA_character_, n_strategies)   # "trend" or "accum"
peak_price   <- rep(NA_real_,   n_strategies)
stopped_out  <- rep(FALSE,      n_strategies)
stop_price   <- rep(NA_real_,   n_strategies)
stop_bar     <- rep(NA_integer_, n_strategies)
bar_counter  <- rep(0L,         n_strategies)

# Load persisted state if available
cat("\n[STARTUP] Loading persisted state...\n")
load_state()

# === Main Loop ===
while (TRUE) {
  for (i in 1:n_strategies) {
    tryCatch({
      cat(paste0("\n[", Sys.time(), "] Strategy ", i, ": ", pairs[i], " (", candles_pairs[i], ")\n"))

      candles <- get_candles_with_retry(
        pair       = candles_pairs[i],
        numcandles = 300,
        timeframe  = timeframes[i]
      )

      close  <- as.numeric(Cl(candles))
      n_bars <- length(close)
      bar_counter[i] <- bar_counter[i] + 1L

      # ── TREND SIGNAL ─────────────────────────────────────
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

      sma_vals  <- SMA(close, n = sma_period)
      rsi_vals  <- RSI(close, n = rsi_period)
      last_rsi  <- as.numeric(last(rsi_vals))
      last_sma  <- as.numeric(last(sma_vals))
      last_close <- as.numeric(last(close))

      above_sma  <- !is.na(last_sma)  && last_close > last_sma
      rsi_ok     <- !is.na(last_rsi)  && last_rsi > rsi_min
      ema_signal <- probability >= long_threshold

      trend_signal <- if (ema_signal && above_sma && rsi_ok) "long" else "neutral"

      # ── ACCUMULATION SIGNAL ──────────────────────────────
      # Rolling high over last accum_high_bars bars
      high_window  <- tail(close, accum_high_bars)
      rolling_high <- max(high_window, na.rm = TRUE)
      dip_from_high <- (rolling_high - last_close) / rolling_high

      # Rolling low over last accum_low_bars bars
      low_window   <- tail(close, accum_low_bars)
      rolling_low  <- min(low_window, na.rm = TRUE)
      bounce_off_low <- (last_close - rolling_low) / rolling_low

      deep_dip   <- !is.na(dip_from_high)  && dip_from_high  >= accum_drawdown_pct
      oversold   <- !is.na(last_rsi)        && last_rsi       <  accum_rsi_max
      bounced    <- !is.na(bounce_off_low)  && bounce_off_low >= accum_bounce_pct

      accum_signal <- if (deep_dip && oversold && bounced) "long" else "neutral"

      cat(sprintf(
        "  TREND  — EMA: %.0f%%  SMA50: %s  RSI: %.1f  → %s\n",
        probability * 100,
        ifelse(above_sma, "above", "below"),
        ifelse(!is.na(last_rsi), last_rsi, NA),
        trend_signal
      ))
      cat(sprintf(
        "  ACCUM  — dip: %.1f%%  RSI: %.1f  bounce: %.1f%%  → %s\n",
        dip_from_high  * 100,
        ifelse(!is.na(last_rsi), last_rsi, NA),
        bounce_off_low * 100,
        accum_signal
      ))

      # ── COOLDOWN CHECK (trend stops only) ────────────────
      if (stopped_out[i]) {
        bars_since_stop <- bar_counter[i] - stop_bar[i]
        price_recovered <- !is.na(stop_price[i]) &&
                           last_close >= stop_price[i] * (1 + reentry_pct)
        cooldown_done   <- bars_since_stop >= cooldown_bars

        if (cooldown_done && price_recovered) {
          cat(sprintf("  ✅ Re-entry unlocked (%d bars, +%.1f%% recovery)\n",
                      bars_since_stop, reentry_pct * 100))
          stopped_out[i] <- FALSE
          stop_price[i]  <- NA_real_
          stop_bar[i]    <- NA_integer_
        } else {
          cat(sprintf("  ⏳ Cooldown: %d/%d bars | recovered: %s\n",
                      bars_since_stop, cooldown_bars,
                      ifelse(price_recovered, "YES", "NO")))
        }
      }

      # ── POSITION MANAGEMENT ──────────────────────────────
      if (in_position[i]) {

        # Update trailing peak
        if (is.na(peak_price[i]) || last_close > peak_price[i])
          peak_price[i] <- last_close

        # Choose trailing stop based on current mode
        ts <- if (!is.na(mode[i]) && mode[i] == "accum") trailing_stop_accum else trailing_stop_trend

        # Trailing stop hit?
        if (!is.na(peak_price[i]) && last_close < peak_price[i] * (1 - ts)) {
          cat(sprintf("  🛑 Trailing stop hit! [%s mode]  Peak: %.4f  Now: %.4f  Drop: %.1f%%\n",
                      mode[i], peak_price[i], last_close,
                      (1 - last_close / peak_price[i]) * 100))
          effective_side <- "neutral"
          in_position[i] <- FALSE
          peak_price[i]  <- NA_real_
          # Only apply cooldown for trend stops
          if (!is.na(mode[i]) && mode[i] == "trend") {
            stopped_out[i] <- TRUE
            stop_price[i]  <- last_close
            stop_bar[i]    <- bar_counter[i]
          }
          mode[i] <- NA_character_

        } else if (!is.na(mode[i]) && mode[i] == "trend" && trend_signal == "neutral") {
          # Clean trend exit
          cat("  📤 Clean trend exit (signal neutral)\n")
          effective_side <- "neutral"
          in_position[i] <- FALSE
          peak_price[i]  <- NA_real_
          mode[i]        <- NA_character_

        } else if (!is.na(mode[i]) && mode[i] == "accum" && trend_signal == "long") {
          # Trend mode takes over — exit accum cleanly, re-enter as trend next bar
          cat("  🔄 Trend signal recovered — handing off from accum → trend next bar\n")
          effective_side  <- "neutral"
          in_position[i]  <- FALSE
          peak_price[i]   <- NA_real_
          mode[i]         <- NA_character_

        } else {
          effective_side <- "long"
        }

      } else {
        # Not in position
        if (trend_signal == "long" && !stopped_out[i]) {
          cat("  📈 TREND entry\n")
          effective_side  <- "long"
          in_position[i]  <- TRUE
          mode[i]         <- "trend"
          peak_price[i]   <- last_close

        } else if (accum_signal == "long") {
          # Accumulation entry — no cooldown restriction
          cat("  🛒 ACCUMULATION entry (deep dip + oversold + bounced)\n")
          effective_side  <- "long"
          in_position[i]  <- TRUE
          mode[i]         <- "accum"
          peak_price[i]   <- last_close

        } else {
          effective_side <- "neutral"
        }
      }

      cat(sprintf(
        "  📊 Side: %-7s | Mode: %-6s | InPos: %s | StoppedOut: %s\n",
        effective_side,
        ifelse(is.na(mode[i]), "—", mode[i]),
        ifelse(in_position[i], "YES", "NO"),
        ifelse(stopped_out[i], "YES", "NO")
      ))

      # ── EXECUTE IF SIDE CHANGED ───────────────────────────
      if (last_sides[i] != effective_side) {
        cat(sprintf("  🔄 %s → %s — sending setBot\n", last_sides[i], effective_side))
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
        save_state()
      } else {
        cat(sprintf("  ✓ Side unchanged: %s — no action\n", effective_side))
      }

    }, error = function(e) {
      cat(paste0("  ❌ Error in strategy ", i, ": ", e$message, "\n"))
    })
  }

  save_state()
  cat(paste0("\n[", Sys.time(), "] Cycle complete. Sleeping 6h...\n"))
  Sys.sleep(60 * 60 * 6)
}
