
choppy_indicator = function(OHLC, period_choppy) {
        names(OHLC) <- tolower(names(OHLC) )
        ALL_atr <- ATR(OHLC[, c("high", "low", "close")], n = period_choppy)
        ALL_atr <- ALL_atr[, c("trueHigh", "trueLow", "tr", "atr") ]
        ## TrueRange
        tr <- ALL_atr[, c("tr")]
        ## trueHigh, highest high over number_periods
        trueHigh <- ALL_atr[, c("trueHigh")]
        ## trueLow, lowest low over n -> number_periods
        trueLow <- ALL_atr[, c("trueLow")]
        ## Constant Sliding Window moves along the index instead of accumulating the previous one
        n = length(tr)
        sum_tr = rep(0,n); max_trueHigh = rep(0,n); min_trueLow = rep(0,n)
        for (i in period_choppy:n) {
                sum_tr[i] = sum(tr[i:(i-period_choppy + 1)])
                max_trueHigh[i] = max(trueHigh[(i-period_choppy + 1):i])
                min_trueLow[i] = min(trueLow[(i-period_choppy + 1):i])
        }
        true_range <- max_trueHigh - min_trueLow
        ## Choppiness Index
        choppy <- 100 * (log10(sum_tr / true_range)) / (log10(period_choppy) )
        return(choppy)
}
