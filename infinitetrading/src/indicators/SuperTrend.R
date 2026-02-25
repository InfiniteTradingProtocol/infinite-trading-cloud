#Richard Clare - SuperTrend.R
#ST = SuperTrend(OHLC = candles, periods = 10, multiplier = 3,chart=TRUE,lag=5,priceType="hi_lo")

SuperTrend <- function(OHLC, periods = 10, multiplier = 3,lag = 0, candle_close=TRUE,chart = TRUE,labeling=FALSE,return_object=FALSE,priceType="hl2",trailing=TRUE,pctg=0){
  require("TTR"); require("quantmod");
  n = nrow(OHLC); ST = c(); ST$signals = rep(0,n); ST$indicator = rep(0,n); ST$Upper_band = rep(0, n); ST$distance_to_indicator=rep(0,n); ST$Lower_band = rep(0, n); ST$trend = rep(0,n); prices = rep(0,n)
  close = Cl(OHLC); high = Hi(OHLC); low = Lo(OHLC); open = Op(OHLC)
  ST$candles = OHLC
  atr = ATR(HLC(OHLC)[,-1], n = periods); trend = "up"
  for(i in (periods+lag + 1):n){
    if (priceType=="hl2") { prices[i] = (high[i-lag]+low[i-lag])/2 }
    else if (priceType=="oc2") { prices[i] = (open[i-lag]+close[i-lag])/2 }
    ST$Lower_band[i] = prices[i] - multiplier * atr[i-lag,2]
    ST$Upper_band[i] = prices[i] + multiplier * atr[i-lag,2]
    if (trailing) {
      if (trend == "up") { ST$Lower_band[i] = max(ST$Lower_band[i],ST$Lower_band[i-1]) }
      else if (trend == "down") { ST$Upper_band[i] = min(ST$Upper_band[i],ST$Upper_band[i-1]) }
    }
    if(close[i] >= ST$Upper_band[i]){
      trend = "up"
      ST$indicator[i] = ST$Lower_band[i]
      ST$trend[i] = 1
      if (candle_close && i < n) { ST$signals[i] = ST$signals[i-1]; ST$signals[i+1] = 1 }
      else { ST$signals[i] = 1 }
    }
    else if(close[i] <= ST$Lower_band[i]){
      trend = "down"
      ST$indicator[i] = ST$Upper_band[i]
      ST$trend[i] = 0
      if (candle_close && i < n) { ST$signals[i] = ST$signals[i-1]; ST$signals[i+1] = -1 }
      else { ST$signals[i] = -1 }
    }
    else {
      if (trend == "up") { ST$trend[i] = 1; ST$indicator[i] = ST$Lower_band[i]; }
      else if (trend == "down") { ST$trend[i] = 0; ST$indicator[i] = ST$Upper_band[i] }
    }
    ST$distance_to_indicator[i] = (close[i] - ST$indicator[i])/max(abs(close[(i-periods):i] - ST$indicator[(i-periods):i]))
  }
  if (labeling) {
    if (pctg > 0) { ST$trend = trend_filter(ST,pctg=pctg) }
  }
  if(chart){
    chartSeries(ts(OHLC))
    uptrend = which(ST$trend == 1)
    downtrend = which(ST$trend ==  0)
    plot(addPoints(x=uptrend,y=(low[uptrend] - 0.02*low[uptrend]),pch=17,col="green",on=1))
    plot(addPoints(x=downtrend,y=(high[downtrend] + 0.02*high[downtrend]),pch=25,col="red",on=1))

    plot(addTA(ts(ST$Lower_band), on = 1, col = 2))
    plot(addTA(ts(ST$Upper_band), on = 1, col = 3))
    plot(addTA(ts(ST$indicator), on = 1, col = 4))
  }
  if (labeling) { return(ST$trend)  }
  else if (return_object) {
    return(ST)
  }
  else{ return(ST$distance_to_indicator) }
}
#require("rgdax")
#candles = public_candles(product_id = "BTC-USD", start = NULL, end = NULL, granularity = 86400)
#SuperTrend(OHLC = candles, periods = 10, multiplier = 3)
