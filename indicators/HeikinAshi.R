##########################################
#### Heikin-Ashi & Clare-Ashi candles ####
#### Author: R. Clare                 ####
#### Copyright Tradery 2020           ####
##########################################

heikin_ashi <- function(OHLC,type="mean",chart=FALSE) {
  close = Cl(OHLC)
  open = Op(OHLC)
  low = Lo(OHLC)
  high = Hi(OHLC)
  n = nrow(OHLC)
  if (type=="mean") { 
    heikin_close = (open+close+low+high)/4
  }
  else if (type == "median") {
    heikin_close= rep(0,n)
    for (i in 1:n) {
      heikin_close[i] = median(open[i],close[i],low[i],high[i])
    }
  }
  heikin_open = rep(0,n)
  heikin_high = rep(0,n)
  heikin_low = rep(0,n)
  
  heikin_open[1] = open[1]
  heikin_high[1] = max(high[1],heikin_close[1],heikin_open[1])
  heikin_low[1] = min(low[1],heikin_close[1],heikin_open[1])

  for (i in 2:n) {
    heikin_open[i] = (heikin_open[i-1]+heikin_close[i-1])/2
    heikin_high[i] = max(high[i],heikin_close[i],heikin_open[i])
    heikin_low[i] = min(low[i],heikin_close[i],heikin_open[i])
  }
  OHLC[,1] = OHLC[,1]
  OHLC[,2] = heikin_close
  OHLC[,3] = heikin_high
  OHLC[,4] = heikin_open
  OHLC[,5] = heikin_close
  if (chart) { chartSeries(ts(OHLC)) } 
  return(OHLC)
}
