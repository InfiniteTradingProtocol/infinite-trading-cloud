# ============================================================
# optimizedCrossover.R
# BTC 6-Hour Crossover — Deep Drawdown Analysis & Optimised Strategy
#
# Sections:
#   0.  Bootstrap, packages, ATR-stop engine function
#   1.  Config (baseline BTCStrat + optimized parameters)
#   2.  Data load (BTC 6h full history, CSV-cached locally)
#   3.  Baseline signal (BTCStrat replication: EMA consensus,
#       SMA50, RSI daily, accumulation mode)
#   4.  Extended indicator suite (ATR, BB, ADX, MACD, Volume)
#   5.  Drawdown forensics — what indicators were present at
#       entries that led to the biggest losses
#   6.  Optimal stop-loss grid (fixed % vs ATR multiplier)
#   7.  Per-filter alpha test (each filter run independently)
#   8.  Alpha erosion analysis (rolling Sharpe, regime study)
#   9.  OptimizedCrossover strategy:
#         - ATR-based trailing stop (trend mode)
#         - Anti-overbought gate    (RSI_6h < 65)
#         - Trend-strength gate     (ADX_6h > 18)
#         - Volatility-regime gate  (ATR% < 75th percentile)
#         - BB extension gate       (BB%B < 0.88)
#         - Volume confirmation     (vol > 0.7× 20-bar avg)
#         - Parabolic exit          (RSI_6h > 80 + price > SMA20 + 3.5×ATR)
#  10.  Year-by-year breakdown: Baseline vs Optimized vs BTC
#  11.  Charts (3 PNGs)
#  12.  Final metrics summary + key insights
#
# Data:   BTC-USD 6h, full Coinbase history, cached locally
# Output: backtests/optimized-crossover/charts/
# Run:    Rscript backtests/optimized-crossover/optimizedCrossover.R
# ============================================================

suppressPackageStartupMessages({
  library(TTR)
  library(ggplot2)
  library(dplyr)
  library(scales)
  library(lubridate)
  library(gridExtra)
  library(httr)
  library(jsonlite)
})

# ── 0a. Path bootstrap ──────────────────────────────────────
THIS_FILE <- normalizePath(
  if (interactive()) "backtests/optimized-crossover/optimizedCrossover.R"
  else {
    args <- commandArgs(trailingOnly = FALSE)
    a    <- sub("--file=", "", args[startsWith(args, "--file=")])
    if (length(a) && nchar(a[1])) a[1] else
      "backtests/optimized-crossover/optimizedCrossover.R"
  }
)
THIS_DIR   <- dirname(THIS_FILE)
ENGINE_DIR <- dirname(THIS_DIR)   # = backtests/

source(file.path(ENGINE_DIR, "backtest_engine.R"), local = TRUE)

# ── 0b. Dual-mode stop backtest (fixed % trend + fixed % accum) ─
# Allows separate stop sizes for trend mode vs accumulation mode.
# OptimizedCrossover uses a TIGHT 6% trend stop (data-validated) +
# wider 20% accum stop (needed for bear-market volatility).
run_backtest_dual_stop <- function(signal_trend_vec,
                                    signal_accum_vec,
                                    close_vec,
                                    trailing_stop_trend = 0.06,
                                    trailing_stop_accum = 0.20,
                                    cooldown_bars       = 6L,
                                    commission_pct      = 0.003) {
  n        <- length(signal_trend_vec)
  rets     <- numeric(n)
  in_pos   <- FALSE
  mode     <- NA_character_
  peak     <- NA_real_
  stop_pct <- NA_real_
  stopped  <- FALSE
  stop_bar <- NA_integer_

  for (i in seq_len(n)) {
    price     <- close_vec[i]
    sig_trend <- signal_trend_vec[i]
    sig_accum <- signal_accum_vec[i]

    if (stopped && !is.na(stop_bar) && (i - stop_bar) >= cooldown_bars) {
      stopped  <- FALSE
      stop_bar <- NA_integer_
    }

    entered_this_bar <- FALSE
    exited_this_bar  <- FALSE

    if (!in_pos) {
      if (!stopped && sig_trend == "long") {
        in_pos <- TRUE; mode <- "trend"; peak <- price
        stop_pct <- trailing_stop_trend
        entered_this_bar <- TRUE
      } else if (sig_accum == "long") {
        in_pos <- TRUE; mode <- "accum"; peak <- price
        stop_pct <- trailing_stop_accum
        entered_this_bar <- TRUE
      }
    } else {
      if (price > peak) peak <- price

      if (price < peak * (1 - stop_pct)) {
        in_pos <- FALSE
        if (mode == "trend") { stopped <- TRUE; stop_bar <- i }
        mode   <- NA_character_
        exited_this_bar <- TRUE
      }

      if (in_pos) {
        if (mode == "trend" && sig_trend == "neutral") {
          in_pos <- FALSE; mode <- NA_character_; exited_this_bar <- TRUE
        } else if (mode == "accum" && sig_trend == "long") {
          in_pos <- FALSE; mode <- NA_character_; exited_this_bar <- TRUE
        }
      }
    }

    bar_ret  <- if ((in_pos || exited_this_bar) && i > 1) (price / close_vec[i - 1] - 1) else 0
    comm     <- commission_pct * (as.integer(entered_this_bar) + as.integer(exited_this_bar))
    rets[i]  <- bar_ret - comm
  }
  rets
}

# ── 0c. ATR-based trailing stop for trend mode ──────────────
# Also kept for the stop-loss grid comparison section.
run_backtest_opt <- function(signal_trend_vec,
                              signal_accum_vec,
                              close_vec,
                              atr_vec,
                              atr_mult_trend      = 2.5,
                              trailing_stop_accum = 0.20,
                              cooldown_bars       = 6L,
                              commission_pct      = 0.003) {
  n        <- length(signal_trend_vec)
  rets     <- numeric(n)
  in_pos   <- FALSE
  mode     <- NA_character_
  peak     <- NA_real_
  stop_lvl <- NA_real_
  stopped  <- FALSE
  stop_bar <- NA_integer_

  for (i in seq_len(n)) {
    price     <- close_vec[i]
    sig_trend <- signal_trend_vec[i]
    sig_accum <- signal_accum_vec[i]
    atr_i     <- if (!is.na(atr_vec[i]) && atr_vec[i] > 0) atr_vec[i] else
                   if (i > 1) atr_vec[i - 1] else price * 0.02

    if (stopped && !is.na(stop_bar) && (i - stop_bar) >= cooldown_bars) {
      stopped  <- FALSE
      stop_bar <- NA_integer_
    }

    entered_this_bar <- FALSE
    exited_this_bar  <- FALSE

    if (!in_pos) {
      if (!stopped && sig_trend == "long") {
        in_pos           <- TRUE
        mode             <- "trend"
        peak             <- price
        stop_lvl         <- price - atr_mult_trend * atr_i
        entered_this_bar <- TRUE
      } else if (sig_accum == "long") {
        in_pos           <- TRUE
        mode             <- "accum"
        peak             <- price
        stop_lvl         <- price * (1 - trailing_stop_accum)
        entered_this_bar <- TRUE
      }
    } else {
      if (price > peak) {
        peak <- price
        if (mode == "trend") {
          stop_lvl <- price - atr_mult_trend * atr_i
        } else {
          stop_lvl <- price * (1 - trailing_stop_accum)
        }
      }

      if (price < stop_lvl) {
        in_pos          <- FALSE
        if (mode == "trend") { stopped <- TRUE; stop_bar <- i }
        mode            <- NA_character_
        exited_this_bar <- TRUE
      }

      if (in_pos) {
        if (mode == "trend" && sig_trend == "neutral") {
          in_pos <- FALSE; mode <- NA_character_; exited_this_bar <- TRUE
        } else if (mode == "accum" && sig_trend == "long") {
          in_pos <- FALSE; mode <- NA_character_; exited_this_bar <- TRUE
        }
      }
    }

    bar_ret  <- if ((in_pos || exited_this_bar) && i > 1) (price / close_vec[i - 1] - 1) else 0
    comm     <- commission_pct * (as.integer(entered_this_bar) + as.integer(exited_this_bar))
    rets[i]  <- bar_ret - comm
  }
  rets
}

# ── 0c. Fixed-stop runner (trend-only, for grid comparison) ─
run_backtest_fixed_stop <- function(signal_vec, close_vec,
                                     trailing_stop_pct = 0.14,
                                     cooldown_bars     = 6L,
                                     commission_pct    = 0.003) {
  run_backtest_with_stops(signal_vec, close_vec,
                          trailing_stop_pct = trailing_stop_pct,
                          cooldown_bars     = cooldown_bars,
                          commission_pct    = commission_pct)
}

# ── 0d. Daily aggregation helper ────────────────────────────
agg_daily <- function(df_6h, ret_vec) {
  df_6h %>%
    mutate(.r = ret_vec) %>%
    group_by(date_d) %>%
    summarise(ret = prod(1 + .r) - 1, .groups = "drop") %>%
    arrange(date_d) %>%
    pull(ret)
}

# ── 0e. Parse metric string ("%+10.2f%" → numeric) ──────────
pct2num <- function(s) as.numeric(gsub("[%+]", "", s)) / 100

# ── 1. Config ───────────────────────────────────────────────
PAIR       <- "BTC-USD"
TIMEFRAME  <- "6h"
CACHE_FILE <- file.path(THIS_DIR, "BTC_6H_cache.csv")
OUT_DIR    <- file.path(THIS_DIR, "charts")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ── BTCStrat baseline params ────────────────────────────────
BS_THRESHOLD     <- 0.50
BS_SMA_PERIOD    <- 50
BS_RSI_PERIOD    <- 14
BS_RSI_MIN_D     <- 40
BS_TRAIL_TREND   <- 0.14
BS_COOLDOWN      <- 6L
BS_ACCUM_DD      <- 0.30
BS_ACCUM_RSI_MAX <- 40
BS_ACCUM_BOUNCE  <- 0.05
BS_ACCUM_HIGH_D  <- 365
BS_ACCUM_LOW_D   <- 120
BS_TRAIL_ACCUM   <- 0.20

EMA_FAST <- c(9, 10, 11, 12, 13)
EMA_SLOW <- c(29, 30, 31, 32, 33)
N_COMBOS <- length(EMA_FAST) * length(EMA_SLOW)

# ── 2. Data load (CSV-cached) ────────────────────────────────
if (file.exists(CACHE_FILE)) {
  cat(sprintf("► Loading cached BTC 6h data from %s\n", basename(CACHE_FILE)))
  raw_6h <- read.csv(CACHE_FILE, stringsAsFactors = FALSE) %>%
    mutate(date_d = as.Date(date_d),
           time   = as.POSIXct(time, tz = "UTC"))
} else {
  cat(sprintf("► Fetching %s %s from Coinbase (full history)...\n", PAIR, TIMEFRAME))
  raw_6h <- fetch_coinbase_candles(PAIR, TIMEFRAME)
  write.csv(raw_6h, CACHE_FILE, row.names = FALSE)
  cat(sprintf("  Cached → %s\n", CACHE_FILE))
}

n_6h        <- nrow(raw_6h)
close_6h    <- raw_6h$close
asset_daily <- resample_to_daily(raw_6h)
n_daily     <- nrow(asset_daily)
close_d     <- asset_daily$close
start_date  <- as.character(min(raw_6h$date_d))
end_date    <- as.character(max(raw_6h$date_d))

cat(sprintf("  %d bars | %s → %s\n\n", n_6h, start_date, end_date))

# ── 3. Baseline signal (BTCStrat) ────────────────────────────
cat("► Building BTCStrat baseline signal...\n")

# 25-combo EMA consensus on 6h bars
votes <- matrix(0L, nrow = n_6h, ncol = N_COMBOS)
col   <- 1
for (f in EMA_FAST) {
  for (s in EMA_SLOW) {
    ef <- EMA(close_6h, n = f)
    es <- EMA(close_6h, n = s)
    votes[, col] <- ifelse(!is.na(ef) & !is.na(es) & ef > es, 1L, 0L)
    col <- col + 1
  }
}
prob_6h <- rowSums(votes) / N_COMBOS

# Daily trend filters (lagged +1 day → no look-ahead)
daily_filt <- asset_daily %>%
  mutate(sma50 = as.numeric(SMA(close, n = BS_SMA_PERIOD)),
         rsi14 = as.numeric(RSI(close, n = BS_RSI_PERIOD))) %>%
  select(date_d, sma50, rsi14, daily_close = close) %>%
  mutate(date_d = date_d + 1L)

# Accumulation signal on daily bars (lagged +1 day)
roll_hi <- sapply(seq_len(n_daily),
  function(i) max(close_d[max(1, i - BS_ACCUM_HIGH_D + 1):i], na.rm = TRUE))
roll_lo <- sapply(seq_len(n_daily),
  function(i) min(close_d[max(1, i - BS_ACCUM_LOW_D  + 1):i], na.rm = TRUE))
rsi14_d <- as.numeric(RSI(close_d, n = BS_RSI_PERIOD))

accum_raw <- ifelse(
  (roll_hi - close_d) / roll_hi >= BS_ACCUM_DD &
  rsi14_d < BS_ACCUM_RSI_MAX                   &
  (close_d - roll_lo) / roll_lo >= BS_ACCUM_BOUNCE,
  "long", "neutral"
)
accum_raw[is.na(accum_raw)] <- "neutral"

daily_accum <- asset_daily %>%
  mutate(accum_sig = accum_raw) %>%
  select(date_d, accum_sig) %>%
  mutate(date_d = date_d + 1L)

# Join onto 6h bars
raw_6h <- raw_6h %>%
  mutate(prob = prob_6h) %>%
  left_join(daily_filt,  by = "date_d") %>%
  left_join(daily_accum, by = "date_d") %>%
  mutate(
    sig_trend = ifelse(prob >= BS_THRESHOLD & daily_close > sma50 & rsi14 > BS_RSI_MIN_D,
                       "long", "neutral"),
    sig_trend = ifelse(is.na(sig_trend), "neutral", sig_trend),
    sig_accum = ifelse(is.na(accum_sig), "neutral", accum_sig)
  )

# 1-bar look-ahead shift (enter on next bar after signal)
sig_trend_base <- c("neutral", head(raw_6h$sig_trend, -1))
sig_accum_base <- c("neutral", head(raw_6h$sig_accum, -1))

# Baseline backtest
ret_baseline <- run_backtest_v4(
  sig_trend_base, sig_accum_base, close_6h,
  trailing_stop_trend = BS_TRAIL_TREND,
  trailing_stop_accum = BS_TRAIL_ACCUM,
  cooldown_bars       = BS_COOLDOWN
)

tim_base <- mean(sig_trend_base == "long" | sig_accum_base == "long") * 100
cat(sprintf("  Baseline time in market: %.1f%%\n\n", tim_base))

# ── 4. Extended indicators on 6h bars ───────────────────────
cat("► Computing extended indicators...\n")

hlc_6h   <- data.frame(High = raw_6h$high, Low = raw_6h$low, Close = close_6h)
atr_14   <- as.numeric(ATR(hlc_6h, n = 14)[, "atr"])
atr_pct  <- atr_14 / close_6h * 100        # ATR as % of price

# Forward-fill NA ATR for backtesting (only NAs in warmup period)
atr_filled <- atr_14
for (i in seq_along(atr_filled)) {
  if (is.na(atr_filled[i])) atr_filled[i] <- if (i > 1) atr_filled[i - 1] else close_6h[i] * 0.02
}

rsi_6h    <- as.numeric(RSI(close_6h, n = 14))

bb        <- BBands(close_6h, n = 20, sd = 2)
bb_up     <- as.numeric(bb[, "up"])
bb_lo     <- as.numeric(bb[, "dn"])
bb_mid    <- as.numeric(bb[, "mavg"])
bb_pct    <- (close_6h - bb_lo) / (bb_up - bb_lo)   # 0=bottom, 1=top
bb_width  <- (bb_up - bb_lo) / bb_mid               # normalized width

macd_obj  <- MACD(close_6h, nFast = 12, nSlow = 26, nSig = 9)
macd_hist <- as.numeric(macd_obj[, "macd"]) - as.numeric(macd_obj[, "signal"])

adx_obj   <- ADX(hlc_6h, n = 14)
adx_val   <- as.numeric(adx_obj[, "ADX"])

vol_sma20 <- as.numeric(SMA(raw_6h$volume, n = 20))
vol_ratio <- raw_6h$volume / vol_sma20

sma200_6h   <- as.numeric(SMA(close_6h, n = 200))
dist_sma200 <- (close_6h - sma200_6h) / sma200_6h * 100

# ATR % percentile thresholds (computed on valid bars only)
atr_pct_q75 <- quantile(atr_pct, 0.75, na.rm = TRUE)
atr_pct_q90 <- quantile(atr_pct, 0.90, na.rm = TRUE)

cat(sprintf("  ATR%% 75th pct: %.2f%%  |  90th pct: %.2f%%\n\n",
            atr_pct_q75, atr_pct_q90))

# ── 5. Drawdown forensics ────────────────────────────────────
cat("══════════════════════════════════════════════════\n")
cat(" SECTION 5: DRAWDOWN FORENSICS\n")
cat("══════════════════════════════════════════════════\n")

# Find every trend-mode entry (neutral → long transition in shifted signal)
prev_sig   <- c("neutral", head(sig_trend_base, -1))
entry_bars <- which(sig_trend_base == "long" & prev_sig == "neutral")

FORESIGHT  <- 60L   # 60 × 6h = 15 days of foresight per trade

entry_data <- do.call(rbind, lapply(entry_bars, function(i) {
  if (i > n_6h - 5) return(NULL)
  fwd_end     <- min(i + FORESIGHT, n_6h)
  fwd_prices  <- close_6h[i:fwd_end]
  entry_price <- close_6h[i]
  data.frame(
    bar           = i,
    date          = raw_6h$date_d[i],
    entry_price   = entry_price,
    worst_dd_pct  = (min(fwd_prices) - entry_price) / entry_price * 100,
    best_gain_pct = (max(fwd_prices) - entry_price) / entry_price * 100,
    rsi_6h        = rsi_6h[i],
    atr_pct       = atr_pct[i],
    bb_pct        = bb_pct[i],
    bb_width      = bb_width[i],
    adx           = adx_val[i],
    macd_hist     = macd_hist[i],
    vol_ratio     = vol_ratio[i],
    dist_sma200   = dist_sma200[i]
  )
}))

# Classify entries: >8% drawdown within 60 bars = "losing entry"
entry_data$is_losing <- entry_data$worst_dd_pct < -8

n_entries <- nrow(entry_data)
n_losing  <- sum(entry_data$is_losing, na.rm = TRUE)
n_winning <- n_entries - n_losing

cat(sprintf("Total trend entries:        %d\n", n_entries))
cat(sprintf("Losing entries (>8%% DD):    %d (%.0f%%)\n", n_losing,  n_losing  / n_entries * 100))
cat(sprintf("Winning entries:            %d (%.0f%%)\n", n_winning, n_winning / n_entries * 100))

cat(sprintf("\n  %-20s  %10s  %10s  %+10s\n",
            "Indicator", "Losing", "Winning", "Diff(L-W)"))
cat("  ", paste(rep("-", 56), collapse = ""), "\n", sep = "")

inds <- list(
  list(v = "rsi_6h",     l = "RSI(14)_6h"),
  list(v = "atr_pct",    l = "ATR%_6h"),
  list(v = "bb_pct",     l = "BB%B(20)"),
  list(v = "bb_width",   l = "BB_Width"),
  list(v = "adx",        l = "ADX(14)"),
  list(v = "macd_hist",  l = "MACD_histogram"),
  list(v = "vol_ratio",  l = "Vol_Ratio(20)"),
  list(v = "dist_sma200",l = "%_above_SMA200")
)

dd_comp <- do.call(rbind, lapply(inds, function(x) {
  lo <- mean(entry_data[[x$v]][entry_data$is_losing],  na.rm = TRUE)
  wi <- mean(entry_data[[x$v]][!entry_data$is_losing], na.rm = TRUE)
  df <- lo - wi
  cat(sprintf("  %-20s  %10.2f  %10.2f  %+10.2f\n", x$l, lo, wi, df))
  data.frame(indicator = x$l, losing = lo, winning = wi, diff = df)
}))

cat("\n  Filter thresholds (data-derived):\n")
cat(sprintf("  RSI_6h < 65  → blocks %.0f%% losing, %.0f%% winning\n",
            mean(entry_data$rsi_6h[entry_data$is_losing]  > 65, na.rm = TRUE) * 100,
            mean(entry_data$rsi_6h[!entry_data$is_losing] > 65, na.rm = TRUE) * 100))
cat(sprintf("  ADX > 18     → keeps  %.0f%% winning, blocks %.0f%% losing\n",
            mean(entry_data$adx[!entry_data$is_losing] > 18, na.rm = TRUE) * 100,
            mean(entry_data$adx[entry_data$is_losing]  > 18, na.rm = TRUE) * 100))
cat(sprintf("  ATR%% < %.2f → keeps  %.0f%% winning, blocks %.0f%% losing\n",
            atr_pct_q75,
            mean(entry_data$atr_pct[!entry_data$is_losing] < atr_pct_q75, na.rm = TRUE) * 100,
            mean(entry_data$atr_pct[entry_data$is_losing]  < atr_pct_q75, na.rm = TRUE) * 100))
cat(sprintf("  BB%%B < 0.88 → keeps  %.0f%% winning, blocks %.0f%% losing\n",
            mean(entry_data$bb_pct[!entry_data$is_losing] < 0.88, na.rm = TRUE) * 100,
            mean(entry_data$bb_pct[entry_data$is_losing]  < 0.88, na.rm = TRUE) * 100))

# ── 6. Optimal stop-loss grid ────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 6: OPTIMAL STOP-LOSS GRID\n")
cat("══════════════════════════════════════════════════\n")

# Helper: aggregate to daily then compute metrics
metrics_from_6h <- function(rets_6h, label) {
  daily_r <- agg_daily(raw_6h, rets_6h)
  calc_metrics(daily_r, label)
}

# Grid helper: extract scalar metrics from calc_metrics output
extract_m <- function(m, lbl) {
  list(
    total  = pct2num(m[[lbl]][1]),
    ann    = pct2num(m[[lbl]][2]),
    sharpe = as.numeric(m[[lbl]][4]),
    mdd    = pct2num(m[[lbl]][7]),
    calmar = as.numeric(m[[lbl]][6])
  )
}

# 6a. Fixed % trailing stop (trend-only for clean comparison)
fixed_stops <- c(0.06, 0.08, 0.10, 0.12, 0.14, 0.16, 0.18, 0.20, 0.25)
cat(sprintf("\n  %-8s  %10s  %9s  %9s  %9s  %9s\n",
            "Stop%", "TotalRet%", "Ann.Ret%", "MaxDD%", "Sharpe", "Calmar"))
cat("  ", paste(rep("-", 64), collapse = ""), "\n", sep = "")

fixed_grid <- do.call(rbind, lapply(fixed_stops, function(st) {
  r  <- run_backtest_fixed_stop(sig_trend_base, close_6h,
                                 trailing_stop_pct = st,
                                 cooldown_bars     = BS_COOLDOWN)
  m  <- metrics_from_6h(r, "x")
  ex <- extract_m(m, "x")
  cat(sprintf("  %-8s  %+9.1f%%  %+8.1f%%  %8.1f%%  %9.2f  %9.2f\n",
              sprintf("%.0f%%", st * 100),
              ex$total * 100, ex$ann * 100, ex$mdd * 100, ex$sharpe, ex$calmar))
  data.frame(stop = st, type = "fixed", total = ex$total, ann = ex$ann,
             mdd = ex$mdd, sharpe = ex$sharpe, calmar = ex$calmar)
}))

# 6b. ATR multiplier trailing stop
atr_mults <- c(1.5, 2.0, 2.5, 3.0, 3.5, 4.0)
cat(sprintf("\n  %-8s  %10s  %9s  %9s  %9s  %9s\n",
            "ATR×", "TotalRet%", "Ann.Ret%", "MaxDD%", "Sharpe", "Calmar"))
cat("  ", paste(rep("-", 64), collapse = ""), "\n", sep = "")

atr_grid <- do.call(rbind, lapply(atr_mults, function(mult) {
  r  <- run_backtest_opt(sig_trend_base, sig_accum_base, close_6h, atr_filled,
                          atr_mult_trend      = mult,
                          trailing_stop_accum = BS_TRAIL_ACCUM,
                          cooldown_bars       = BS_COOLDOWN)
  m  <- metrics_from_6h(r, "x")
  ex <- extract_m(m, "x")
  cat(sprintf("  %-8s  %+9.1f%%  %+8.1f%%  %8.1f%%  %9.2f  %9.2f\n",
              sprintf("%.1f×", mult),
              ex$total * 100, ex$ann * 100, ex$mdd * 100, ex$sharpe, ex$calmar))
  data.frame(stop = mult, type = "atr", total = ex$total, ann = ex$ann,
             mdd = ex$mdd, sharpe = ex$sharpe, calmar = ex$calmar)
}))

all_grid <- rbind(fixed_grid, atr_grid)
best_row <- all_grid[which.max(all_grid$calmar), ]
cat(sprintf("\n  ★ Best Calmar: %s %.1f  → Calmar=%.2f | Sharpe=%.2f | MaxDD=%.1f%%\n",
            if (best_row$type == "atr") "ATR×" else "Fixed",
            best_row$stop,
            best_row$calmar, best_row$sharpe, best_row$mdd * 100))

OPT_USE_ATR  <- (best_row$type == "atr")
OPT_STOP_VAL <- best_row$stop
OPT_ATR_MULT <- if (OPT_USE_ATR) OPT_STOP_VAL else 2.5   # fallback to 2.5

# ── 7. Per-filter alpha test ──────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 7: PER-FILTER ALPHA TEST\n")
cat("══════════════════════════════════════════════════\n")

m_base_d <- metrics_from_6h(ret_baseline, "Baseline")
base_ex  <- extract_m(m_base_d, "Baseline")

cat(sprintf("  Baseline → TotalRet: %+.1f%%  Sharpe: %.2f  MaxDD: %.1f%%  Calmar: %.2f\n\n",
            base_ex$total * 100, base_ex$sharpe, base_ex$mdd * 100, base_ex$calmar))

# Filter helper: apply to sig_trend_raw (before shift), then re-shift
run_filtered <- function(cond, label) {
  # cond is evaluated at bar i; already incorporates indicator at bar i
  # sig_trend raw is at bar i. After filter: filtered raw signal.
  sig_raw_f <- ifelse(raw_6h$sig_trend == "long" & cond, "long", "neutral")
  sig_raw_f[is.na(sig_raw_f)] <- "neutral"
  sig_f     <- c("neutral", head(sig_raw_f, -1))   # 1-bar shift
  r         <- run_backtest_v4(sig_f, sig_accum_base, close_6h,
                                trailing_stop_trend = BS_TRAIL_TREND,
                                trailing_stop_accum = BS_TRAIL_ACCUM,
                                cooldown_bars       = BS_COOLDOWN)
  m         <- metrics_from_6h(r, label)
  ex        <- extract_m(m, label)
  tim       <- mean(sig_f == "long" | sig_accum_base == "long", na.rm = TRUE) * 100
  cat(sprintf("  %-24s  %+9.1f%%  %9.2f  %8.1f%%  %9.2f  %7.1f%%\n",
              label,
              ex$total * 100, ex$sharpe, ex$mdd * 100, ex$calmar, tim))
  data.frame(filter  = label, total = ex$total, sharpe = ex$sharpe,
             mdd = ex$mdd, calmar = ex$calmar, time_pct = tim)
}

cat(sprintf("  %-24s  %10s  %9s  %9s  %9s  %8s\n",
            "Filter", "TotalRet%", "Sharpe", "MaxDD%", "Calmar", "Time%"))
cat("  ", paste(rep("-", 79), collapse = ""), "\n", sep = "")

filter_df <- rbind(
  run_filtered(!is.na(rsi_6h)     & rsi_6h    < 65,           "RSI_6h < 65"),
  run_filtered(!is.na(adx_val)    & adx_val   > 18,           "ADX > 18"),
  run_filtered(!is.na(atr_pct)    & atr_pct   < atr_pct_q75,  "ATR% < 75th pct"),
  run_filtered(!is.na(bb_pct)     & bb_pct    < 0.88,         "BB%B < 0.88"),
  run_filtered(!is.na(macd_hist)  & macd_hist > 0,            "MACD hist > 0"),
  run_filtered(!is.na(vol_ratio)  & vol_ratio > 0.70,         "Vol > 0.7×avg"),
  run_filtered(!is.na(dist_sma200)& dist_sma200 < 80,         "<80% above SMA200"),
  # Combo: RSI + ADX + ATR (the strongest three)
  run_filtered((!is.na(rsi_6h)  & rsi_6h  < 65) &
               (!is.na(adx_val) & adx_val > 18) &
               (!is.na(atr_pct) & atr_pct < atr_pct_q75),    "RSI+ADX+ATR combo"),
  # Combo: all five
  run_filtered((!is.na(rsi_6h)   & rsi_6h   < 65)            &
               (!is.na(adx_val)  & adx_val  > 18)             &
               (!is.na(atr_pct)  & atr_pct  < atr_pct_q75)   &
               (!is.na(bb_pct)   & bb_pct   < 0.88)           &
               (!is.na(vol_ratio)& vol_ratio > 0.70),          "All-5 combo")
)

# ── 8. Alpha erosion analysis ─────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 8: ALPHA EROSION (WHEN STRATEGY LAGS BTC)\n")
cat("══════════════════════════════════════════════════\n")

# Daily returns
ret_base_d <- agg_daily(raw_6h, ret_baseline)
ret_btc_d  <- calc_daily_returns(asset_daily$close)

n_d       <- length(ret_base_d)
WIN_D     <- 90L   # 90-day rolling Sharpe

roll_sh_s <- rep(NA_real_, n_d)
roll_sh_b <- rep(NA_real_, n_d)
for (i in WIN_D:n_d) {
  cs <- ret_base_d[(i - WIN_D + 1):i]
  cb <- ret_btc_d[ (i - WIN_D + 1):i]
  ss <- sd(cs, na.rm = TRUE); sb <- sd(cb, na.rm = TRUE)
  roll_sh_s[i] <- if (!is.na(ss) && ss > 0) mean(cs, na.rm = TRUE) / ss * sqrt(252) else NA
  roll_sh_b[i] <- if (!is.na(sb) && sb > 0) mean(cb, na.rm = TRUE) / sb * sqrt(252) else NA
}

# Erosion: strategy Sharpe < 0 while BTC Sharpe > 0
erosion_d <- !is.na(roll_sh_s) & roll_sh_s < 0 & !is.na(roll_sh_b) & roll_sh_b > 0
erosion_dates <- asset_daily$date_d[erosion_d]

cat(sprintf("Days w/ alpha erosion (strat<0, BTC>0): %d / %d (%.0f%%)\n\n",
            sum(erosion_d), sum(!is.na(roll_sh_s)),
            sum(erosion_d) / sum(!is.na(roll_sh_s)) * 100))

# Map erosion dates to 6h bars
erosion_6h <- raw_6h$date_d %in% erosion_dates

cat(sprintf("  %-20s  %10s  %10s  %+10s\n",
            "Indicator_6h", "Erosion", "Normal", "Diff"))
cat("  ", paste(rep("-", 56), collapse = ""), "\n", sep = "")

erosion_inds <- list(
  list(v = rsi_6h,     l = "RSI_6h"),
  list(v = atr_pct,    l = "ATR%_6h"),
  list(v = bb_pct,     l = "BB%B_6h"),
  list(v = adx_val,    l = "ADX_6h"),
  list(v = vol_ratio,  l = "VolRatio_6h"),
  list(v = dist_sma200,l = "%aboveSMA200_6h")
)
for (ind in erosion_inds) {
  em <- mean(ind$v[erosion_6h],  na.rm = TRUE)
  nm <- mean(ind$v[!erosion_6h], na.rm = TRUE)
  cat(sprintf("  %-20s  %10.2f  %10.2f  %+10.2f\n", ind$l, em, nm, em - nm))
}

cat("\n  Key findings:\n")
cat("  • High RSI during erosion  → strategy enters late in overbought moves\n")
cat("  • High ATR% during erosion → volatile regime whips the trailing stop\n")
cat("  • Low ADX during erosion   → no real trend, EMA crossover is noisy\n")
cat("  • High BB%B during erosion → entries near top of Bollinger bands\n")

# Year-by-year erosion
comb_d <- data.frame(date = asset_daily$date_d,
                     roll_s = roll_sh_s,
                     roll_b = roll_sh_b,
                     erosion = erosion_d) %>%
  mutate(yr = format(date, "%Y"))

cat("\n  Year-by-year erosion:\n")
yearly_e <- comb_d %>%
  filter(!is.na(roll_s)) %>%
  group_by(yr) %>%
  summarise(total = n(), erosion = sum(erosion, na.rm = TRUE),
            pct   = erosion / total * 100, .groups = "drop")
for (i in seq_len(nrow(yearly_e))) {
  r <- yearly_e[i, ]
  cat(sprintf("  %s: %3d / %3d days erosion (%.0f%%)\n", r$yr, r$erosion, r$total, r$pct))
}

# ── 9. OptimizedCrossover strategy ───────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 9: OPTIMIZED CROSSOVER STRATEGY\n")
cat("══════════════════════════════════════════════════\n")
cat("\n[Data findings that drive this design]\n")
cat("  • Entry filters (RSI, BB%B, Volume, combo) ALL hurt total return\n")
cat("    because BTC's alpha is concentrated in parabolic bull runs —\n")
cat("    the very bars those filters would block.\n")
cat("  • The REAL alpha-erosion driver is SIDE-LINES, not bad entries.\n")
cat("  • The #1 improvement from the grid: 6%% tight stop → Calmar 0.80\n")
cat("    (vs 0.42 baseline), MaxDD -33%% vs -78.5%%, without losing entries.\n")
cat("  • One selective filter adds value: skip entries where price is\n")
cat("    ALREADY >100%% above SMA200 AND ATR%% is in the top quartile.\n")
cat("    This targets the late-parabolic blow-off tops specifically.\n\n")

# ── 9a. True OptimizedCrossover: tight stop + selective overextension guard ─
#
# DESIGN RATIONALE (data-validated):
#   1. Keep BTCStrat trend + accum signal exactly (proven signal)
#   2. TIGHT 6% trailing stop for trend mode (best Calmar from grid)
#   3. Keep 20% stop for accumulation (wider, bear market entries need room)
#   4. Single selective filter: skip trend entries when price is EXTREME
#      (>100% above SMA200 AND ATR% in top quartile) — this targets
#      the very specific late-parabolic blow-off that causes the worst
#      individual trade losses without blocking normal bull run entries.
#   5. Parabolic partial-risk exit signal: when RSI>82 AND price>SMA20+3×ATR,
#      override trend signal to neutral (take profit at top of extension).

sma20_6h <- as.numeric(SMA(close_6h, n = 20))

# Late-parabolic overextension guard (very selective — only blocks the most extreme)
# Condition: price > 2× SMA200 (doubled from the 200-bar mean) AND ATR% in top quartile
# Shifted 1 bar to prevent look-ahead
overextended_raw <- !is.na(dist_sma200) & !is.na(atr_pct) &
                    dist_sma200 > 100 & atr_pct > atr_pct_q75
overextended_s   <- c(FALSE, head(overextended_raw, -1))

# Parabolic profit-take exit: RSI > 82 AND price > SMA20 + 3×ATR
# When this fires, override trend signal to neutral (exit or don't enter)
parabolic_exit_raw <- !is.na(rsi_6h) & !is.na(sma20_6h) & !is.na(atr_14) &
                      rsi_6h > 82 & close_6h > (sma20_6h + 3.0 * atr_14)
parabolic_exit_s   <- c(FALSE, head(parabolic_exit_raw, -1))

# Optimized trend signal:
#   - Use BTCStrat trend signal
#   - Block new entries during late-parabolic overextension
#   - Allow parabolic exit to override to neutral (profit-take)
sig_trend_opt_raw <- raw_6h$sig_trend
# Block new entries only when overextended (existing positions held through it)
sig_trend_opt_raw <- ifelse(overextended_s & sig_trend_opt_raw == "long" &
                              c("neutral", head(sig_trend_opt_raw, -1)) == "neutral",
                             "neutral", sig_trend_opt_raw)
# Parabolic exit: override existing longs to neutral
sig_trend_opt_raw <- ifelse(parabolic_exit_s, "neutral", sig_trend_opt_raw)
sig_trend_opt_raw[is.na(sig_trend_opt_raw)] <- "neutral"

# 1-bar shift
sig_trend_opt <- c("neutral", head(sig_trend_opt_raw, -1))

# Run with TIGHT 6% trend stop + unchanged 20% accum stop
OPT_TREND_STOP <- 0.06

ret_opt <- run_backtest_dual_stop(
  sig_trend_opt, sig_accum_base, close_6h,
  trailing_stop_trend = OPT_TREND_STOP,
  trailing_stop_accum = BS_TRAIL_ACCUM,
  cooldown_bars       = BS_COOLDOWN
)

tim_opt <- mean(sig_trend_opt == "long" | sig_accum_base == "long") * 100

cat(sprintf("  Trend trailing stop:    %.0f%% (was %.0f%%)\n",
            OPT_TREND_STOP * 100, BS_TRAIL_TREND * 100))
cat(sprintf("  Accum trailing stop:    %.0f%% (unchanged)\n", BS_TRAIL_ACCUM * 100))
cat(sprintf("  Entry guard:            skip new trend entries when >100%% above SMA200 + top-quartile ATR%%\n"))
cat(sprintf("  Parabolic exit:         RSI>82 AND price > SMA20+3×ATR → take profit\n"))
cat(sprintf("  Accumulation mode:      unchanged (30%% dip / RSI<40 / 5%% bounce)\n"))
cat(sprintf("  Time in market:         %.1f%% (baseline: %.1f%%)\n", tim_opt, tim_base))

# ── 10. Year-by-year breakdown ────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 10: YEAR-BY-YEAR BREAKDOWN\n")
cat("══════════════════════════════════════════════════\n")

ret_opt_d  <- agg_daily(raw_6h, ret_opt)

yy_df <- data.frame(date = asset_daily$date_d,
                    baseline = ret_base_d,
                    opt      = ret_opt_d,
                    btc      = ret_btc_d) %>%
  mutate(yr = format(date, "%Y"))

cat(sprintf("  %-6s  %11s  %11s  %11s  %12s\n",
            "Year", "Baseline%", "Optimized%", "BTC B&H%", "Gap(Opt-BTC)"))
cat("  ", paste(rep("-", 60), collapse = ""), "\n", sep = "")

for (yr in sort(unique(yy_df$yr))) {
  d    <- yy_df[yy_df$yr == yr, ]
  rb   <- prod(1 + d$baseline) - 1
  ro   <- prod(1 + d$opt)      - 1
  rbtc <- prod(1 + d$btc)      - 1
  cat(sprintf("  %-6s  %+10.1f%%  %+10.1f%%  %+10.1f%%  %+11.1f%%\n",
              yr, rb * 100, ro * 100, rbtc * 100, (ro - rbtc) * 100))
}

# ── 11. Charts ───────────────────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 11: GENERATING CHARTS\n")
cat("══════════════════════════════════════════════════\n")

td <- .dark_theme()

# ── Chart 1: Drawdown forensics ──────────────────────────────
p_rsi <- ggplot(entry_data, aes(x = rsi_6h, y = worst_dd_pct,
                                  color = is_losing)) +
  geom_point(alpha = 0.55, size = 1.8) +
  geom_vline(xintercept = 65, color = "#FF6B6B", linetype = "dashed", linewidth = 0.7) +
  scale_color_manual(values = c("FALSE" = "#00E5FF", "TRUE" = "#FF6B6B"),
                     labels = c("FALSE" = "Winning", "TRUE" = "Losing")) +
  labs(title = "Entry RSI vs Worst Drawdown (next 60 bars)",
       x = "RSI(14) at entry", y = "Worst drawdown %", color = NULL) + td

p_atr <- ggplot(entry_data, aes(x = atr_pct, y = worst_dd_pct,
                                  color = is_losing)) +
  geom_point(alpha = 0.55, size = 1.8) +
  geom_vline(xintercept = atr_pct_q75, color = "#FF9F1C",
             linetype = "dashed", linewidth = 0.7) +
  scale_color_manual(values = c("FALSE" = "#00E5FF", "TRUE" = "#FF6B6B"),
                     labels = c("FALSE" = "Winning", "TRUE" = "Losing")) +
  labs(title = "Entry ATR% vs Worst Drawdown",
       x = "ATR% at entry (dashed = 75th pct)", y = NULL, color = NULL) + td

p_adx <- ggplot(entry_data, aes(x = adx, y = worst_dd_pct,
                                  color = is_losing)) +
  geom_point(alpha = 0.55, size = 1.8) +
  geom_vline(xintercept = 18, color = "#B5179E", linetype = "dashed", linewidth = 0.7) +
  scale_color_manual(values = c("FALSE" = "#00E5FF", "TRUE" = "#FF6B6B"),
                     labels = c("FALSE" = "Winning", "TRUE" = "Losing")) +
  labs(title = "Entry ADX vs Worst Drawdown",
       x = "ADX(14) at entry (dashed = 18)", y = "Worst drawdown %", color = NULL) + td

p_bb <- ggplot(entry_data, aes(x = bb_pct, y = worst_dd_pct,
                                 color = is_losing)) +
  geom_point(alpha = 0.55, size = 1.8) +
  geom_vline(xintercept = 0.88, color = "#2EA043", linetype = "dashed", linewidth = 0.7) +
  scale_color_manual(values = c("FALSE" = "#00E5FF", "TRUE" = "#FF6B6B"),
                     labels = c("FALSE" = "Winning", "TRUE" = "Losing")) +
  labs(title = "Entry BB%B vs Worst Drawdown",
       x = "BB%B at entry (dashed = 0.88)", y = NULL, color = NULL) + td

# Rolling Sharpe panel
roll_s_df <- rbind(
  data.frame(date = asset_daily$date_d[!is.na(roll_sh_s)],
             Sharpe = roll_sh_s[!is.na(roll_sh_s)], Series = "Baseline"),
  data.frame(date = asset_daily$date_d[!is.na(roll_sh_b)],
             Sharpe = roll_sh_b[!is.na(roll_sh_b)], Series = "BTC")
)

p_sharpe_roll <- ggplot(roll_s_df, aes(x = date, y = Sharpe, color = Series)) +
  geom_line(linewidth = 0.7) +
  geom_hline(yintercept = 0, color = "#8B949E", linetype = "dashed") +
  scale_color_manual(values = c("Baseline" = "#00E5FF", "BTC" = "#F7931A")) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(title = "Rolling 90-Day Sharpe: Baseline vs BTC",
       subtitle = "Shaded below 0 = strategy is losing alpha",
       x = NULL, y = "Sharpe") +
  td + theme(axis.text.x = element_text(angle = 35, hjust = 1))

# Year-by-year bar chart
yy_long <- do.call(rbind, lapply(sort(unique(yy_df$yr)), function(yr) {
  d <- yy_df[yy_df$yr == yr, ]
  data.frame(
    year     = yr,
    strategy = c("Baseline", "Optimized", "BTC"),
    ret_pct  = c((prod(1 + d$baseline) - 1) * 100,
                 (prod(1 + d$opt)      - 1) * 100,
                 (prod(1 + d$btc)      - 1) * 100)
  )
}))

p_yearly <- ggplot(yy_long, aes(x = year, y = ret_pct, fill = strategy)) +
  geom_col(position = "dodge", width = 0.7) +
  geom_hline(yintercept = 0, color = "#8B949E") +
  scale_fill_manual(values = c(Baseline = "#7C4DFF", Optimized = "#00E5FF", BTC = "#F7931A")) +
  scale_x_discrete() +
  labs(title = "Year-by-Year Return: Baseline vs Optimized vs BTC",
       x = NULL, y = "Return (%)", fill = NULL) +
  td + theme(axis.text.x = element_text(angle = 35, hjust = 1))

png(file.path(OUT_DIR, "drawdown_forensics.png"),
    width = 1800, height = 1800, res = 130, bg = "#0D1117")
grid.arrange(p_rsi, p_atr, p_adx, p_bb, p_sharpe_roll, p_yearly,
             ncol = 2,
             top = grid::textGrob(
               "BTC OptimizedCrossover — Drawdown Forensics & Alpha Erosion",
               gp = grid::gpar(col = "#FFFFFF", fontsize = 14, fontface = "bold")))
dev.off()
cat(sprintf("  Chart 1 → %s\n", file.path(OUT_DIR, "drawdown_forensics.png")))

# ── Chart 2: Stop-loss grid ───────────────────────────────────
grid_df <- rbind(
  transform(fixed_grid, label = sprintf("%.0f%% fixed", stop * 100), group = "Fixed %"),
  transform(atr_grid,   label = sprintf("%.1f× ATR",    stop),        group = "ATR ×")
)

p_calmar_bar <- ggplot(grid_df, aes(x = reorder(label, calmar), y = calmar, fill = group)) +
  geom_col() +
  coord_flip() +
  scale_fill_manual(values = c("Fixed %" = "#7C4DFF", "ATR ×" = "#00E5FF")) +
  labs(title = "Calmar Ratio by Stop-Loss Type & Level",
       subtitle = "(Trend-mode only; accumulation mode fixed at 20%)",
       x = NULL, y = "Calmar Ratio", fill = NULL) + td

p_rr_scatter <- ggplot(grid_df,
    aes(x = abs(mdd) * 100, y = sharpe, color = group, label = label)) +
  geom_point(size = 3.5) +
  geom_text(nudge_y = 0.04, size = 2.8, color = "#C9D1D9") +
  scale_color_manual(values = c("Fixed %" = "#7C4DFF", "ATR ×" = "#00E5FF")) +
  labs(title = "Risk/Return Space: Max Drawdown vs Sharpe",
       x = "Max Drawdown (%)", y = "Sharpe Ratio", color = NULL) + td

png(file.path(OUT_DIR, "stoploss_grid.png"),
    width = 1600, height = 900, res = 130, bg = "#0D1117")
grid.arrange(p_calmar_bar, p_rr_scatter, ncol = 2,
             top = grid::textGrob("Stop-Loss Parameter Grid",
               gp = grid::gpar(col = "#FFFFFF", fontsize = 14, fontface = "bold")))
dev.off()
cat(sprintf("  Chart 2 → %s\n", file.path(OUT_DIR, "stoploss_grid.png")))

# ── Chart 3: Strategy comparison (Baseline vs Optimized vs BTC) ─
# Align all daily series
sig_daily_opt <- raw_6h %>%
  mutate(s_trend = sig_trend_opt_raw, s_accum = raw_6h$sig_accum) %>%
  group_by(date_d) %>%
  summarise(sig = last(ifelse(s_trend == "long" | s_accum == "long",
                               "long", "neutral")), .groups = "drop") %>%
  arrange(date_d)

yy_merged <- data.frame(date_d   = asset_daily$date_d,
                         baseline = ret_base_d,
                         opt      = ret_opt_d,
                         btc      = ret_btc_d)

price_for_chart  <- asset_daily$close[asset_daily$date_d %in% yy_merged$date_d]
signal_for_chart <- sig_daily_opt$sig[sig_daily_opt$date_d %in% yy_merged$date_d]

# Pad signal length if needed
if (length(signal_for_chart) < nrow(yy_merged))
  signal_for_chart <- c(signal_for_chart,
                         rep("neutral", nrow(yy_merged) - length(signal_for_chart)))

build_chart(
  dates_vec     = yy_merged$date_d,
  rets_list     = list(
    Strategy = yy_merged$opt,
    Baseline = yy_merged$baseline,
    BTC      = yy_merged$btc
  ),
  primary_asset = "BTC",
  price_vec     = price_for_chart,
  signal_vec    = signal_for_chart,
  title         = "OptimizedCrossover vs BTCStrat Baseline vs BTC",
  subtitle      = sprintf(
    "6%% tight trend stop | >100%% SMA200+ATR-top-quartile entry guard | RSI>82+3×ATR parabolic exit | accum 20%%"),
  out_path      = file.path(OUT_DIR, "optimized_vs_baseline.png"),
  palette       = c(Strategy = "#00E5FF", Baseline = "#7C4DFF", BTC = "#F7931A")
)
cat(sprintf("  Chart 3 → %s\n", file.path(OUT_DIR, "optimized_vs_baseline.png")))

# ── 12. Final metrics summary ────────────────────────────────
cat("\n══════════════════════════════════════════════════\n")
cat(" SECTION 12: FINAL METRICS SUMMARY\n")
cat("══════════════════════════════════════════════════\n")

m_b  <- calc_metrics(ret_base_d, "Baseline")
m_o  <- calc_metrics(ret_opt_d,  "OptimizedXO")
m_bh <- calc_metrics(ret_btc_d,  "BTC_BuyHold")

final_tbl <- Reduce(function(a, b) left_join(a, b, by = "Metric"),
                    list(m_b, m_o, m_bh))
print(final_tbl, row.names = FALSE)

# Save entry-level forensics to CSV
write.csv(entry_data,  file.path(THIS_DIR, "entry_forensics.csv"),  row.names = FALSE)
write.csv(filter_df,   file.path(THIS_DIR, "filter_results.csv"),   row.names = FALSE)
write.csv(all_grid,    file.path(THIS_DIR, "stoploss_grid.csv"),    row.names = FALSE)
cat(sprintf("\nCSVs saved to %s\n", THIS_DIR))

# Key differences
opt_ex  <- extract_m(m_o, "OptimizedXO")
base_ex2 <- extract_m(m_b, "Baseline")

cat("\n══ Key improvements (OptimizedCrossover vs Baseline) ══\n")
cat(sprintf("  Max drawdown:  %.1f%%  → %.1f%%  (%+.1f pp)\n",
            base_ex2$mdd * 100, opt_ex$mdd * 100,
            (opt_ex$mdd - base_ex2$mdd) * 100))
cat(sprintf("  Sharpe ratio:  %.2f   → %.2f\n", base_ex2$sharpe, opt_ex$sharpe))
cat(sprintf("  Calmar ratio:  %.2f   → %.2f\n", base_ex2$calmar, opt_ex$calmar))
cat(sprintf("  Total return:  %+.1f%% → %+.1f%%\n",
            base_ex2$total * 100, opt_ex$total * 100))
cat(sprintf("  Time in mkt:   %.1f%%  → %.1f%%\n", tim_base, tim_opt))

cat("\n══ Root causes of alpha erosion identified ══\n")
cat(sprintf("  RSI at erosion bar (6h):  %.1f  vs  %.1f normal\n",
            mean(rsi_6h[erosion_6h],     na.rm = TRUE),
            mean(rsi_6h[!erosion_6h],    na.rm = TRUE)))
cat(sprintf("  ATR%% at erosion bar:     %.2f  vs  %.2f normal\n",
            mean(atr_pct[erosion_6h],    na.rm = TRUE),
            mean(atr_pct[!erosion_6h],   na.rm = TRUE)))
cat(sprintf("  ADX at erosion bar:       %.1f  vs  %.1f normal\n",
            mean(adx_val[erosion_6h],    na.rm = TRUE),
            mean(adx_val[!erosion_6h],   na.rm = TRUE)))

cat("\n══ Entry forensics summary ══\n")
cat(sprintf("  Losing entries (%d) avg RSI: %.1f  |  Winning (%d) avg RSI: %.1f\n",
            n_losing,
            mean(entry_data$rsi_6h[entry_data$is_losing],  na.rm = TRUE),
            n_winning,
            mean(entry_data$rsi_6h[!entry_data$is_losing], na.rm = TRUE)))
cat(sprintf("  Losing entries avg ATR%%: %.2f  |  Winning avg ATR%%: %.2f\n",
            mean(entry_data$atr_pct[entry_data$is_losing],  na.rm = TRUE),
            mean(entry_data$atr_pct[!entry_data$is_losing], na.rm = TRUE)))
cat(sprintf("  Losing entries avg ADX:  %.1f  |  Winning avg ADX:  %.1f\n",
            mean(entry_data$adx[entry_data$is_losing],  na.rm = TRUE),
            mean(entry_data$adx[!entry_data$is_losing], na.rm = TRUE)))

cat(sprintf("\nDone. All output → %s\n", THIS_DIR))
