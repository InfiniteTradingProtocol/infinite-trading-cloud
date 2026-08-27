source("~/infinitetrading/src/strategies/main.R")

network = "optimism"
protocol = "dhedge"
pool = "0xa74d3d3227f2e95157d22a09f68ea5e2259329fa"
pair = "VELO-USDC"
slippage = 0.3
share = 100
platform = "odos"
max_usd = 10000
threshold = 1

rsiPeriod <- 14
smaPeriod <- 21
last_side <- "none"

is_true <- function(value) {
  length(value) == 1 && !is.na(value) && isTRUE(value)
}

while (1) {
  candles <- get_candles_with_retry(pair = "VELO-USD", numcandles = 100, timeframe = "1d")
  n <- NROW(candles)

  # === Indicators ===
  close_prices <- Cl(candles)
  open_prices <- Op(candles)
  high_prices <- Hi(candles)
  low_prices <- Lo(candles)

  sma21 <- SMA(close_prices, n = smaPeriod)
  rsi <- RSI(close_prices, n = rsiPeriod)

  # === Trend detection ===
  uptrend <- close_prices > sma21
  downtrend <- close_prices < sma21


  # === Divergence ===
  rolling_max <- function(x, n) rollapply(x, width = n, FUN = max, fill = NA, align = "right")
  rolling_min <- function(x, n) rollapply(x, width = n, FUN = min, fill = NA, align = "right")

  bearishDiv <- rsi < rolling_max(rsi, 15) & close_prices > rolling_max(close_prices, 15)
  bullishDiv <- rsi > rolling_min(rsi, 15) & close_prices < rolling_min(close_prices, 15)

  # === Candlestick Patterns ===
  bearishEngulfing <- lag(close_prices) > lag(open_prices) &
                      close_prices < open_prices &
                      close_prices < lag(open_prices) &
                      open_prices > lag(close_prices)

  shootingStar <- (high_prices - pmax(close_prices, open_prices)) > 2 * abs(close_prices - open_prices) &
                  (pmin(open_prices, close_prices) - low_prices) < (high_prices - low_prices) * 0.25

  hangingMan <- (high_prices - low_prices) > 3 * abs(open_prices - close_prices) &
                (close_prices - low_prices) / (high_prices - low_prices + 0.001) < 0.3

  bearishCandle <- bearishEngulfing | shootingStar | hangingMan

  bullishEngulfing <- lag(close_prices) < lag(open_prices) &
                      close_prices > open_prices &
                      close_prices > lag(open_prices) &
                      open_prices < lag(close_prices)

  morningStar <- n > 2 & lag(close_prices, 2) < lag(open_prices, 2) &
                 abs(lag(open_prices) - lag(close_prices)) < (lag(high_prices) - lag(low_prices)) * 0.3 &
                 close_prices > (lag(open_prices, 2) + lag(close_prices, 2)) / 2

  hammer <- (high_prices - low_prices) > 3 * abs(open_prices - close_prices) &
            (close_prices - low_prices) / (high_prices - low_prices + 0.001) > 0.6

  bullishCandle <- bullishEngulfing | morningStar | hammer

  # === Final logic ===
  recent_rsi <- rsi[(n-7):(n-1)]
  rsiBounce <- any(recent_rsi <= 60, na.rm = TRUE) && is_true(rsi[n] > 60)
  rsiTop <- is_true(rsi[n] < 80) && any(recent_rsi >= 80, na.rm = TRUE)
  rsiBottom <- any(recent_rsi <= 30, na.rm = TRUE) && is_true(rsi[n] > 30)
  sma_distance <- (close_prices[n] - sma21[n]) / sma21[n]
  priceNearSMA <- is_true(sma_distance < 0.015) && is_true(sma_distance > 0)
  todayDowntrend = ifelse(close_prices[n] < close_prices[n-1],1,0)
  todayUptrend = ifelse(close_prices[n] > close_prices[n-1],1,0)
  inUptrend <- uptrend[n]
  inDowntrend <- downtrend[n]

  longSignal <- FALSE
  neutralSignal <- FALSE

  if (is_true(inUptrend)) {
    longSignal <- rsiBounce || priceNearSMA || (!is_true(bearishCandle[n-1]) && !is_true(bearishCandle[n])) || is_true(todayUptrend == 1) || (is_true(bullishCandle[n]) && !is_true(bearishCandle[n-1]))
    neutralSignal <- (rsiTop || is_true(bearishDiv[n]) || is_true(bearishDiv[n-1]) || is_true(bearishCandle[n]) || is_true(bearishCandle[n-1])) && is_true(todayDowntrend == 1)
  } else if (is_true(inDowntrend)) {
    longSignal <- ((any(recent_rsi < 30, na.rm = TRUE) && (is_true(bullishDiv[n]) || is_true(bullishDiv[n-1]) || is_true(bullishCandle[n]) || is_true(bullishCandle[n-1])) ) && is_true(todayUptrend == 1)) || rsiBottom
    neutralSignal <- (is_true(bearishCandle[n-1]) || is_true(bearishCandle[n])) && is_true(todayDowntrend == 1)
  }

  if (longSignal) {
    side <- "long"
  } else if (neutralSignal) {
    side <- "neutral"
  } else {
    side <- "hold"
  }

  # === Log and Execute ===
  decimals <- 5
  msg <- paste(
    "pool:", pool, "(", network, ")", "/ side:", side,
    "/ RSI:", round(rsi[n], 2), "/ price:", round(close_prices[n], decimals),
    "/ SMA21:", round(sma21[n], decimals), "/ priceNearSMA:",priceNearSMA,
    "/ Trend:", ifelse(inUptrend, "Up", ifelse(inDowntrend, "Down", "Flat")),
    "/ Buy:", longSignal, "/ Sell:", neutralSignal,
    "/ bearishCandle[n]:", bearishCandle[n],"/ bearishCandle[n-1]:", bearishCandle[n-1],
    "/ bullishCandle[n]:", bullishCandle[n],"/ bullishCandle[n-1]:", bullishCandle[n-1],
    "/ rsiTop:", rsiTop,"/ rsiBottom:", rsiBottom,
    "/ bullishDiv[n]:", bullishDiv[n],"/ bearishDiv[n]:", bearishDiv[n],
    "/ bullishDiv[n-1]:", bullishDiv[n-1],"/ bearishDiv[n-1]:", bearishDiv[n-1],
    "/ todayUptrend:", todayUptrend,"/ todayDowntrend:", todayDowntrend
  )

  print(msg); discord(msg)

  if (side != last_side) {
    response <- itp_api(endpoint = "setBot", params = list(
      apiKey = apiKey,
      protocol = protocol,
      network = network,
      pool = pool,
      pair = pair,
      side = side,
      max_usd = max_usd,
      slippage = slippage,
      threshold = threshold,
      share = share,
      platform = platform
    ))
    if (itp_api_success(response)) {
      last_side <- side
    } else {
      message <- if (!is.null(response$message)) response$message[[1]] else "unknown API error"
      cat(sprintf("Bot update rejected by API: %s\n", message))
    }
  }

  print(side)
  Sys.sleep(60 * 60 * 4)  # sleep for 1 day (or adjust if using new candles)
}
