library(TTR)
library(uantmod)
library(dplyr)
library(zoo)

# === Load your OHLCV data ===
# Example: df <- read.csv("data.csv")
# Ensure columns: Date, Open, High, Low, Close, Volume

# Placeholder example:
# df <- getSymbols("SPY", from = "2020-01-01", auto.assign = FALSE)

# --- Rename columns if needed ---
# colnames(df) <- c("Open", "High", "Low", "Close", "Volume", "Adjusted")

# === Indicator Calculations ===
df$sma21 <- SMA(df$Close, n = 21)
df$rsi <- RSI(df$Close, n = 14)

# === Trend Detection ===
df$uptrend <- df$Close > df$sma21
df$downtrend <- df$Close < df$sma21

# === RSI Crosses ===
cross_under <- function(x, level) c(FALSE, diff(x < level & lag(x) >= level) == 1)
cross_over  <- function(x, level) c(FALSE, diff(x > level & lag(x) <= level) == 1)

df$rsiCrossBelow80 <- cross_under(df$rsi, 80)
df$rsiCrossAbove60 <- cross_over(df$rsi, 60)
df$rsiCrossAbove30 <- cross_over(df$rsi, 30)
df$rsiCrossBelow30 <- cross_under(df$rsi, 30)
df$rsiCrossAbove50 <- cross_over(df$rsi, 50)

# === RSI Divergence (Simple) ===
rolling_max <- function(x, n) rollapply(x, width = n, FUN = max, fill = NA, align = "right")
rolling_min <- function(x, n) rollapply(x, width = n, FUN = min, fill = NA, align = "right")

df$bearishDiv <- df$rsi < rolling_max(df$rsi, 10) & df$Close > rolling_max(df$Close, 10)
df$bullishDiv <- df$rsi > rolling_min(df$rsi, 10) & df$Close < rolling_min(df$Close, 10)

# === Candlestick Pattern Logic ===
df$bearishEngulfing <- lag(df$Close) > lag(df$Open) &
                       df$Close < df$Open &
                       df$Close < lag(df$Open) &
                       df$Open > lag(df$Close)

df$shootingStar <- (df$High - pmax(df$Close, df$Open)) > 2 * abs(df$Close - df$Open) &
                   (pmin(df$Open, df$Close) - df$Low) < (df$High - df$Low) * 0.25

df$hangingMan <- (df$High - df$Low) > 3 * abs(df$Open - df$Close) &
                 (df$Close - df$Low) / (df$High - df$Low + 0.001) < 0.3

df$bearishCandle <- df$bearishEngulfing | df$shootingStar | df$hangingMan

df$bullishEngulfing <- lag(df$Close) < lag(df$Open) &
                       df$Close > df$Open &
                       df$Close > lag(df$Open) &
                       df$Open < lag(df$Close)

df$morningStar <- lag(df$Close, 2) < lag(df$Open, 2) &
                  abs(lag(df$Open) - lag(df$Close)) < (lag(df$High) - lag(df$Low)) * 0.3 &
                  df$Close > (lag(df$Open, 2) + lag(df$Close, 2)) / 2

df$hammer <- (df$High - df$Low) > 3 * abs(df$Open - df$Close) &
             (df$Close - df$Low) / (df$High - df$Low + 0.001) > 0.6

df$bullishCandle <- df$bullishEngulfing | df$morningStar | df$hammer

# === Entry Filters ===
df$priceNearSMA <- ((df$Close - df$sma21) / df$sma21) < 0.015 &
                   ((df$Close - df$sma21) / df$sma21) > 0

df$rsiBounce <- df$rsi < 50 & df$rsiCrossAbove60

# === Entry / Exit Logic ===
df$buyUptrend <- df$uptrend &
                 !lag(uantmod::position(df), default = FALSE) &
                 (df$rsiBounce | df$priceNearSMA)

df$sellUptrend <- lag(uantmod::position(df), default = FALSE) &
                  df$uptrend &
                  (df$rsiCrossBelow80 & lag(df$rsi) > 90 |
                   df$bearishDiv |
                   df$bearishCandle |
                   df$Close < df$sma21)

df$buyDowntrend <- df$downtrend &
                   !lag(uantmod::position(df), default = FALSE) &
                   ((df$rsi < 30 & (df$bullishDiv | df$bullishCandle)) |
                   (lag(df$rsi) < 30 & df$rsiCrossAbove30))

df$sellDowntrend <- lag(uantmod::position(df), default = FALSE) &
                    df$downtrend &
                    (df$rsi > 50 & df$rsiCrossAbove50 |
                     df$rsiCrossBelow30 |
                     df$Close > df$sma21)

# === Trade Execution ===
signals <- rep(NA, nrow(df))
position <- rep(0, nrow(df))  # 0 = flat, 1 = long

for (i in 2:nrow(df)) {
  if (isTRUE(df$buyUptrend[i] | df$buyDowntrend[i]) && position[i-1] == 0) {
    signals[i] <- 1
    position[i] <- 1
  } else if (isTRUE(df$sellUptrend[i] | df$sellDowntrend[i]) && position[i-1] == 1) {
    signals[i] <- -1
    position[i] <- 0
  } else {
    position[i] <- position[i-1]
  }
}

df$signals <- signals
df$position <- position
# === Side Signal Output ===
df$side <- case_when(
  df$signals == 1  ~ "long",
  df$signals == -1 ~ "neutral",
  TRUE             ~ "hold"
)

