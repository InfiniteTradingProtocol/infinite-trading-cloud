# ============================================================
# backtest_engine.R
# Reusable backtesting library for Infinite Trading strategies
#
# Provides:
#   - fetch_coinbase_candles()   → paginated Coinbase OHLCV
#   - resample_to_daily()        → collapse intraday → daily close
#   - calc_daily_returns()       → % return vector from close prices
#   - run_backtest()             → equity curve from signal + returns
#                                  (commission_pct applied on each entry/exit)
#   - align_series()             → align multiple return vectors by date
#   - calc_metrics()             → Sharpe, Sortino, Calmar, MaxDD, etc.
#   - build_chart()              → 5-panel pro dark chart + PNG save
#
# All functions are no-lookahead safe.
# Required packages: TTR, ggplot2, dplyr, scales, lubridate,
#                    gridExtra, httr, jsonlite
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

# Source the Coinbase fetcher (same directory as this file)
source(file.path(dirname(normalizePath(
  ifelse(interactive(), "backtests/backtest_engine.R",
         commandArgs(trailingOnly = FALSE) |>
           (\(a) a[startsWith(a, "--file=")])() |>
           (\(a) if (length(a)) sub("--file=", "", a) else "backtests/backtest_engine.R")())
)), "data", "fetch_coinbase_candles.R"), local = TRUE)


# ------------------------------------------------------------------
# resample_to_daily(df)
#   Takes a candle df from fetch_coinbase_candles() and returns
#   a daily df with the last-close of each day.
# ------------------------------------------------------------------
resample_to_daily <- function(df) {
  df %>%
    group_by(date_d) %>%
    summarise(close = last(close), .groups = "drop") %>%
    arrange(date_d)
}


# ------------------------------------------------------------------
# calc_daily_returns(close_vec)
#   Returns a numeric vector of daily % returns (first bar = 0).
# ------------------------------------------------------------------
calc_daily_returns <- function(close_vec) {
  c(0, diff(close_vec) / head(close_vec, -1))
}


# ------------------------------------------------------------------
# run_backtest(signal_vec, asset_returns)
#   signal_vec    : character vector "long" | "neutral" (no lookahead,
#                   already shifted by caller)
#   asset_returns : numeric daily return vector (same length)
#   commission_pct: one-way commission rate deducted on each entry/exit
#                   (default 0.0003 = 0.03%)
#   Returns       : numeric strategy return vector
#
#   NOTE: caller must shift signal by 1 bar before passing here.
#         i.e. signal_vec <- c("neutral", head(raw_signal, -1))
# ------------------------------------------------------------------
run_backtest <- function(signal_vec, asset_returns, commission_pct = 0.003) {
  n       <- length(signal_vec)
  rets    <- numeric(n)
  in_pos  <- FALSE

  for (i in seq_len(n)) {
    sig <- signal_vec[i]

    if (!in_pos && sig == "long") {
      in_pos  <- TRUE
      rets[i] <- asset_returns[i] - commission_pct   # entry cost
    } else if (in_pos && sig != "long") {
      in_pos  <- FALSE
      rets[i] <- -commission_pct                     # exit cost (flat bar)
    } else if (in_pos) {
      rets[i] <- asset_returns[i]
    }
  }

  rets
}


# ------------------------------------------------------------------
# run_backtest_with_stops(signal_vec, close_vec,
#                         trailing_stop_pct, reentry_pct,
#                         cooldown_bars)
#
#   Trailing stop + smart re-entry logic:
#
#   STOP: while long, if price drops trailing_stop_pct below the
#         rolling high → exit and enter cooldown.
#
#   RE-ENTRY (two conditions, both must pass):
#     1. cooldown_bars have elapsed since stop-out
#     2. price has recovered reentry_pct above the effective reference price
#        (confirms reversal is real, not a dead-cat bounce)
#   After both conditions met, re-entry allowed on next "long" signal.
#
#   NORMAL EXIT: signal flips to "neutral" → exit immediately,
#                no cooldown needed (clean signal-driven exit).
#
#   Args:
#     trailing_stop_pct  : fraction below peak to stop (default 0.08 = 8%)
#     reentry_pct        : price must recover this % above reference price
#                          before re-entry is allowed (default 0.05 = 5%)
#     cooldown_bars      : minimum bars to wait after stop regardless
#                          of price recovery (default 3 days)
#     reentry_lookback   : if set (e.g. 120), the re-entry reference price is
#                          lowered to min(stop_price, rolling_high over last N
#                          bars), so the threshold decays as the market trades
#                          lower after a stop-out → faster re-entries.
#                          NULL (default) = classic behaviour (fixed stop_price).
# ------------------------------------------------------------------
run_backtest_with_stops <- function(signal_vec,
                                    close_vec,
                                    trailing_stop_pct  = 0.08,
                                    reentry_pct        = 0.05,
                                    cooldown_bars      = 3,
                                    reentry_lookback   = NULL,
                                    commission_pct     = 0.003) {
  n            <- length(signal_vec)
  rets         <- numeric(n)
  in_pos       <- FALSE
  peak         <- NA_real_
  stopped      <- FALSE
  stop_price   <- NA_real_   # price at which we were stopped out
  stop_bar     <- NA_integer_ # bar index when stopped

  for (i in seq_len(n)) {
    raw_sig <- signal_vec[i]
    price   <- close_vec[i]

    # ── Check if cooldown has expired and price recovered ──
    if (stopped) {
      bars_since_stop <- i - stop_bar
      cooldown_done   <- bars_since_stop >= cooldown_bars

      # Effective reference: optionally decay using rolling high
      # Looks back reentry_lookback bars from CURRENT bar (not stop_bar),
      # so once N bars pass since the peak, the high of that window
      # falls below stop_price and the threshold decays naturally.
      if (!is.null(reentry_lookback) && !is.na(stop_price)) {
        lb_start      <- max(1L, i - as.integer(reentry_lookback) + 1L)
        rolling_high  <- max(close_vec[lb_start:i], na.rm = TRUE)
        ref_price     <- min(stop_price, rolling_high)
      } else {
        ref_price     <- stop_price
      }

      price_recovered <- price >= ref_price * (1 + reentry_pct)

      if (cooldown_done && price_recovered) {
        stopped    <- FALSE   # cleared to re-enter on next long signal
        stop_price <- NA_real_
        stop_bar   <- NA_integer_
      }
    }

    # ── Entry / exit logic ──────────────────────────────────
    entered_this_bar <- FALSE
    exited_this_bar  <- FALSE

    if (!in_pos) {
      # Enter if signal is long and not in cooldown
      if (raw_sig == "long" && !stopped) {
        in_pos           <- TRUE
        peak             <- price
        entered_this_bar <- TRUE
      }
    } else {
      # Update trailing peak while in position
      if (price > peak) peak <- price

      # Trailing stop triggered
      if (price < peak * (1 - trailing_stop_pct)) {
        in_pos          <- FALSE
        stopped         <- TRUE
        stop_price      <- price
        stop_bar        <- i
        exited_this_bar <- TRUE
      }

      # Clean signal exit (no cooldown — strategy said get out)
      if (in_pos && raw_sig == "neutral") {
        in_pos          <- FALSE
        exited_this_bar <- TRUE
        # no stopped flag — can re-enter immediately on next long signal
      }
    }

    # ── Bar return ──────────────────────────────────────────
    bar_ret  <- if ((in_pos || exited_this_bar) && i > 1) (price / close_vec[i - 1] - 1) else 0
    comm     <- commission_pct * (as.integer(entered_this_bar) + as.integer(exited_this_bar))
    rets[i]  <- bar_ret - comm
  }

  rets
}


# ------------------------------------------------------------------
# run_backtest_v4(signal_trend_vec, signal_accum_vec, close_vec,
#                daily_dates_vec, ...)
#
#   V4 DUAL-MODE STRATEGY:
#   ┌─────────────────────────────────────────────────────────┐
#   │ TREND mode  : existing crossover signal (signal_trend)  │
#   │               8% trailing stop, 3-day cooldown          │
#   │                                                         │
#   │ ACCUMULATION mode : fires during deep bear markets      │
#   │   Trigger (daily, joined to 6h):                        │
#   │     • price > 35% below its 180-day high (deep dip)     │
#   │     • RSI(14) daily < 35 (oversold)                     │
#   │     • price bounced ≥ 10% off its 90-day low            │
#   │       (not catching a falling knife)                     │
#   │   Uses wider 15% trailing stop (higher vol environment) │
#   │   Exits on: 15% stop OR trend signal turns long         │
#   │   (hands off to trend mode when uptrend resumes)        │
#   └─────────────────────────────────────────────────────────┘
#
#   Args:
#     signal_trend_vec  : "long"/"neutral" per 6h bar (trend signal)
#     signal_accum_vec  : "long"/"neutral" per 6h bar (accumulation signal)
#     close_vec         : 6h close prices
#     trailing_stop_trend : trailing stop for trend entries (default 0.08)
#     trailing_stop_accum : trailing stop for accum entries (default 0.15)
#     cooldown_bars       : bars to wait after trend stop (default 12 = 3 days)
# ------------------------------------------------------------------
run_backtest_v4 <- function(signal_trend_vec,
                            signal_accum_vec,
                            close_vec,
                            trailing_stop_trend = 0.08,
                            trailing_stop_accum = 0.15,
                            cooldown_bars       = 12L,
                            commission_pct      = 0.003) {
  n          <- length(signal_trend_vec)
  rets       <- numeric(n)
  in_pos     <- FALSE
  mode       <- NA_character_   # "trend" or "accum"
  peak       <- NA_real_
  stopped    <- FALSE
  stop_bar   <- NA_integer_

  for (i in seq_len(n)) {
    price      <- close_vec[i]
    sig_trend  <- signal_trend_vec[i]
    sig_accum  <- signal_accum_vec[i]

    # ── Cooldown: only applies after trend stop-outs ──────
    if (stopped) {
      if ((i - stop_bar) >= cooldown_bars) {
        stopped  <- FALSE
        stop_bar <- NA_integer_
      }
    }

    # ── Position management ───────────────────────────────
    entered_this_bar <- FALSE
    exited_this_bar  <- FALSE

    if (!in_pos) {
      if (!stopped && sig_trend == "long") {
        # Trend entry (higher priority)
        in_pos <- TRUE; mode <- "trend"; peak <- price
        entered_this_bar <- TRUE
      } else if (sig_accum == "long") {
        # Accumulation entry — no cooldown restriction
        in_pos <- TRUE; mode <- "accum"; peak <- price
        entered_this_bar <- TRUE
      }
    } else {
      if (price > peak) peak <- price
      ts <- if (mode == "trend") trailing_stop_trend else trailing_stop_accum

      # Stop triggered
      if (price < peak * (1 - ts)) {
        in_pos <- FALSE
        if (mode == "trend") { stopped <- TRUE; stop_bar <- i }
        mode <- NA_character_
        exited_this_bar <- TRUE
      }

      # Clean exits
      if (in_pos) {
        if (mode == "trend" && sig_trend == "neutral") {
          in_pos <- FALSE; mode <- NA_character_
          exited_this_bar <- TRUE
        } else if (mode == "accum" && sig_trend == "long") {
          # Trend signal recovered — hand off cleanly (re-enter as trend next bar)
          in_pos <- FALSE; mode <- NA_character_
          exited_this_bar <- TRUE
        }
      }
    }

    bar_ret  <- if ((in_pos || exited_this_bar) && i > 1) (price / close_vec[i - 1] - 1) else 0
    comm     <- commission_pct * (as.integer(entered_this_bar) + as.integer(exited_this_bar))
    rets[i]  <- bar_ret - comm
  }

  rets
}


# ------------------------------------------------------------------
# align_series(named_list_of_date_ret_pairs)
#   Input : named list where each element is list(dates, rets)
#   Output: list with $dates (common Date vector) and $rets (named
#           matrix, one column per series)
#
# Example:
#   aligned <- align_series(list(
#     Strategy = list(dates = d1, rets = r1),
#     MORPHO   = list(dates = d2, rets = r2),
#     BTC      = list(dates = d3, rets = r3)
#   ))
# ------------------------------------------------------------------
align_series <- function(named_list) {
  common_dates <- as.Date(Reduce(intersect, lapply(named_list, function(x) as.character(x$dates))))
  common_dates <- sort(common_dates)
  rets_mat <- sapply(named_list, function(x) x$rets[x$dates %in% common_dates])
  list(dates = common_dates, rets = rets_mat)
}


# ------------------------------------------------------------------
# calc_metrics(rets, label)
#   rets  : numeric daily return vector
#   label : column name string
#   Returns a data.frame with Metric | label columns
# ------------------------------------------------------------------
calc_metrics <- function(rets, label) {
  rets      <- as.numeric(rets)
  n_days    <- length(rets)
  total_ret <- prod(1 + rets) - 1
  ann_ret   <- (1 + total_ret)^(252 / n_days) - 1
  ann_vol   <- sd(rets, na.rm = TRUE) * sqrt(252)
  sharpe    <- ann_ret / ann_vol
  downside  <- rets[rets < 0]
  sortino   <- ann_ret / (sd(downside, na.rm = TRUE) * sqrt(252))
  cum_curve <- cumprod(1 + rets)
  max_dd    <- min(cum_curve / cummax(cum_curve) - 1)
  win_rate  <- mean(rets > 0, na.rm = TRUE)
  calmar    <- ann_ret / abs(max_dd)
  data.frame(
    Metric = c("Total Return", "Ann. Return", "Ann. Volatility",
               "Sharpe Ratio", "Sortino Ratio", "Calmar Ratio",
               "Max Drawdown", "Win Rate"),
    V = c(
      sprintf("%+.1f%%", total_ret * 100),
      sprintf("%+.1f%%", ann_ret * 100),
      sprintf("%.1f%%",  ann_vol * 100),
      sprintf("%.2f",    sharpe),
      sprintf("%.2f",    sortino),
      sprintf("%.2f",    calmar),
      sprintf("%.1f%%",  max_dd * 100),
      sprintf("%.1f%%",  win_rate * 100)
    ), stringsAsFactors = FALSE
  ) %>% setNames(c("Metric", label))
}


# ------------------------------------------------------------------
# build_metrics_table(rets_list)
#   rets_list: named list of return vectors e.g. list(Strategy=r1, BTC=r2)
#   Returns combined metrics data.frame
# ------------------------------------------------------------------
build_metrics_table <- function(rets_list) {
  tbls <- lapply(names(rets_list), function(n) calc_metrics(rets_list[[n]], n))
  Reduce(function(a, b) left_join(a, b, by = "Metric"), tbls)
}


# ------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------
.dd_vec <- function(rets) {
  c <- cumprod(1 + as.numeric(rets))
  c / cummax(c) - 1
}

.to_long <- function(df, id_col, value_col = "Value", name_col = "Asset") {
  id_vals <- df[[id_col]]
  other   <- setdiff(names(df), id_col)
  do.call(rbind, lapply(other, function(col) {
    data.frame(x = id_vals, asset = col, value = df[[col]], stringsAsFactors = FALSE)
  })) %>% setNames(c(id_col, name_col, value_col))
}

.roll_sharpe <- function(rets, win = 90) {
  result <- rep(NA_real_, length(rets))
  for (i in win:length(rets)) {
    ch <- rets[(i - win + 1):i]
    s  <- sd(ch)
    result[i] <- if (is.na(s) || s == 0) NA else mean(ch) / s * sqrt(252)
  }
  result
}

.dark_theme <- function() {
  theme_minimal(base_size = 11) +
    theme(
      plot.background   = element_rect(fill = "#0D1117", color = NA),
      panel.background  = element_rect(fill = "#0D1117", color = NA),
      panel.grid.major  = element_line(color = "#1E2A38", linewidth = 0.4),
      panel.grid.minor  = element_blank(),
      text              = element_text(color = "#C9D1D9"),
      axis.text         = element_text(color = "#8B949E", size = 9),
      axis.title        = element_text(color = "#C9D1D9", size = 10),
      plot.title        = element_text(color = "#FFFFFF", face = "bold", size = 12),
      plot.subtitle     = element_text(color = "#8B949E", size = 8),
      legend.background = element_rect(fill = "#161B22", color = NA),
      legend.key        = element_rect(fill = "#161B22", color = NA),
      legend.text       = element_text(color = "#C9D1D9"),
      legend.title      = element_blank(),
      plot.margin       = margin(8, 12, 8, 8)
    )
}

.xscale <- function() scale_x_date(date_breaks = "3 months", date_labels = "%b %y")
.xtilt  <- function() theme(axis.text.x = element_text(angle = 35, hjust = 1))


# ------------------------------------------------------------------
# build_chart(
#   dates_vec     : Date vector (common, sorted)
#   rets_list     : named list of daily return vectors
#                   MUST include "Strategy" and primary asset (e.g. "MORPHO")
#   primary_asset : name of the main asset to compare against (string)
#   price_vec     : numeric close prices for primary asset (for signal plot)
#   signal_vec    : character vector "long"/"neutral" (daily, aligned)
#   title         : chart title string
#   subtitle      : chart subtitle string
#   out_path      : full path for PNG output
#   palette       : named colour vector (optional override)
# )
# ------------------------------------------------------------------
build_chart <- function(dates_vec,
                        rets_list,
                        primary_asset,
                        price_vec,
                        signal_vec,
                        title,
                        subtitle  = "",
                        out_path,
                        palette   = NULL) {

  default_pal <- c(
    "Strategy" = "#00E5FF",
    "MORPHO"   = "#7C4DFF",
    "BTC"      = "#F7931A",
    "ETH"      = "#627EEA",
    "AERO"     = "#FF6B6B",
    "SNX"      = "#FF9F1C",
    "AAVE"     = "#B5179E",
    "cbBTC"    = "#F7931A"
  )
  if (!is.null(palette)) {
    for (nm in names(palette)) default_pal[nm] <- palette[nm]
  }
  # ensure primary_asset colour exists
  if (!primary_asset %in% names(default_pal))
    default_pal[[primary_asset]] <- "#A8DADC"

  td <- .dark_theme(); xs <- .xscale(); xt <- .xtilt()

  # Cumulative equity
  cum_list <- lapply(rets_list, function(r) cumprod(1 + as.numeric(r)))
  eq_df    <- as.data.frame(c(list(date = dates_vec), cum_list))
  df_eq    <- .to_long(eq_df, "date", "Value", "Asset")

  # Drawdown (Strategy vs primary)
  dd_df <- data.frame(
    date                     = dates_vec,
    Strategy                 = .dd_vec(rets_list[["Strategy"]]) * 100,
    stringsAsFactors         = FALSE
  )
  dd_df[[primary_asset]] <- .dd_vec(rets_list[[primary_asset]]) * 100
  df_dd <- .to_long(dd_df, "date", "Drawdown", "Asset")

  # Rolling Sharpe (Strategy vs primary)
  sh_df <- data.frame(
    date                 = dates_vec,
    Strategy             = .roll_sharpe(rets_list[["Strategy"]]),
    stringsAsFactors     = FALSE
  )
  sh_df[[primary_asset]] <- .roll_sharpe(rets_list[[primary_asset]])
  df_sh <- .to_long(sh_df, "date", "Sharpe", "Asset")
  df_sh <- df_sh[!is.na(df_sh$Sharpe), ]

  # Signal shading
  df_sig  <- data.frame(date = dates_vec, price = price_vec,
                        side = signal_vec, stringsAsFactors = FALSE)
  rle_s   <- rle(df_sig$side)
  ends    <- cumsum(rle_s$lengths)
  st_idx  <- c(1, head(ends, -1) + 1)
  shade   <- data.frame(xmin  = df_sig$date[st_idx],
                        xmax  = df_sig$date[ends],
                        state = rle_s$values,
                        stringsAsFactors = FALSE)
  shade   <- shade[shade$state == "long", ]

  # Metrics table
  metrics_df <- build_metrics_table(rets_list)
  tbl_theme  <- ttheme_minimal(
    core    = list(
      bg_params = list(fill = rep(c("#161B22","#1C2128"), length.out = 8),
                       col  = "#1E2A38"),
      fg_params = list(col = "#C9D1D9", fontsize = 9)
    ),
    colhead = list(
      bg_params = list(fill = "#21262D", col = "#1E2A38"),
      fg_params = list(col = "#FFFFFF", fontface = "bold", fontsize = 9)
    )
  )
  p_tbl <- tableGrob(metrics_df, rows = NULL, theme = tbl_theme)

  # P1 — Equity
  p1 <- ggplot(df_eq, aes(x = date, y = Value, color = Asset)) +
    geom_line(linewidth = 0.75) +
    scale_color_manual(values = default_pal) +
    scale_y_log10(labels = function(x) paste0(round((x - 1) * 100), "%")) +
    xs + labs(title = title, subtitle = subtitle,
              x = NULL, y = "Growth (×1 start)") +
    td + xt

  # P2 — Drawdown
  dd_pal <- c("Strategy" = default_pal[["Strategy"]],
              setNames(default_pal[[primary_asset]], primary_asset))
  p2 <- ggplot(df_dd, aes(x = date, y = Drawdown, fill = Asset)) +
    geom_area(alpha = 0.4, position = "identity") +
    geom_line(aes(color = Asset), linewidth = 0.5) +
    scale_fill_manual(values  = dd_pal) +
    scale_color_manual(values = dd_pal) +
    xs + labs(title = sprintf("Drawdown — Strategy vs %s", primary_asset),
              x = NULL, y = "Drawdown (%)") + td + xt

  # P3 — Price + Signal
  p3 <- ggplot(df_sig, aes(x = date, y = price)) +
    geom_rect(data = shade,
              aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
              fill = "#00E5FF", alpha = 0.07, inherit.aes = FALSE) +
    geom_line(color = default_pal[[primary_asset]], linewidth = 0.7) +
    xs + scale_y_continuous(labels = dollar_format()) +
    labs(title = sprintf("%s Price + Long Signal Zones (cyan)", primary_asset),
         x = NULL, y = "Price (USD)") + td + xt

  # P4 — Rolling Sharpe
  sh_pal <- c("Strategy" = default_pal[["Strategy"]],
              setNames(default_pal[[primary_asset]], primary_asset))
  p4 <- ggplot(df_sh, aes(x = date, y = Sharpe, color = Asset)) +
    geom_line(linewidth = 0.7) +
    geom_hline(yintercept = 0, color = "#8B949E", linetype = "dashed") +
    geom_hline(yintercept = 1, color = "#2EA043", linetype = "dotted", linewidth = 0.5) +
    scale_color_manual(values = sh_pal) +
    xs + labs(title = "Rolling 90-Day Sharpe Ratio", x = NULL, y = "Sharpe") +
    td + xt

  # Save
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  png(out_path, width = 1600, height = 1900, res = 130, bg = "#0D1117")
  layout_mat <- rbind(c(1,1), c(2,3), c(4,4), c(5,5))
  grid.arrange(p1, p2, p3, p4, p_tbl,
               layout_matrix = layout_mat,
               heights = c(2.2, 1.8, 1.6, 1.5))
  dev.off()
  cat(sprintf("✅  Chart saved → %s\n", out_path))
  invisible(metrics_df)
}
