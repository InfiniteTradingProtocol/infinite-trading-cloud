#######################################################
####                                              #####
#### File: boolean.R                              #####
#### Author: R. Clare                             #####
####                                              #####
#######################################################

#BOOLEAN FUNCTIONS


#crear funciones
#que les paso unas condiciones y me devuelve 1 donde se cumplen y 0 donde no para un vector de precios
#eso se va a usar para comprar/vender con esas señales
#si es de comprar la señal rellenar por 1 donde este y 0 donde no
#si es para vender la señal, rellenar por -1 donde este y por 0 donde no este.
bullish_crossover = function(maType="EMA",nfast=9,nslow=49,candles) {
  close = Cl(candles)
  if (maType == "EMA") { ma_fast = EMA(close,n= nfast); ma_slow = EMA(close,n= nslow) }
  else if (maType == "SMA") { ma_fast = SMA(close,n = nfast); ma_slow = SMA(close,n=nslow) }
  signs = sign(ma_fast - ma_slow)
  
  last_3 = last(signs,3)
  if ( (last_3[1] == -1) & (last_3[2] == 1) &&  (last_3[3] == 1) ) { return(TRUE) }
  else { return(FALSE) }
}
bearish_crossover = function(maType="EMA",nfast=9,nslow=49,candles) {
  close = Cl(candles)
  if (maType == "EMA") { ma_fast = EMA(close,n= nfast); ma_slow = EMA(close,n= nslow) }
  else if (maType == "SMA") { ma_fast = SMA(close,n = nfast); ma_slow = SMA(close,n=nslow) }
  signs = sign(ma_fast - ma_slow)
  
  last_3 = last(signs,3)
  if ( (last_3[1] == 1) & (last_3[2] < 1) &&  (last_3[3] == -1) ) { return(TRUE) }
  else { return(FALSE) }
}


#Returns TRUE if the last price is above/at the upper Donchian channel.
donchian_upper = function(OHLC,period = 20) { }

#Returns TRUE if the last price is below/at the lower Donchian channel using.
donchian_lower = function(OHLC,period = 20) {}

#Returns TRUE if the last price is below/at the mid Donchian channel using.
donchian_mid = function(OHLC,period = 20) {}


#Returns TRUE if the last price is above/at the upper Donchian channel.
bollinger_upper = function(OHLC,period = 20,sd = 2,maType = MA) { }

#Returns TRUE if the last price is below/at the lower Donchian channel using.
bollinger_mid = function(OHLC,period = 20,maType = MA) {}

#Returns TRUE if the last price is below/at the mid Donchian channel using.
bollinger_lower = function(OHLC,period = 20,sd = 2,maType = MA) {}


#Returns TRUE if the last candle shows a bullish hammer.


is_downtrend = function(OHLC,term="short") { 
  
  if (term == "short") { }
  
  else if (term == "mid") { }
  
  else if (term == "long") { }
  
}
bullish_candle = function(OHLC) { 
  if (isTRUE(bullish_hammer(OHLC)) || isTRUE(bullish_harami)) { return(TRUE) }
      return(FALSE)
}

bearish_candle = function(OHLC) { 
  if (isTRUE(bearish_hammer(OHLC)) || isTRUE(bearish_harami)) { return(TRUE) }
  return(FALSE)
}


#provide at least 4 data points

is_peak = function(data,m=13) { 
  data = na.omit(data)
  n = length(data) 
  peaks = find_peaks(data,m=m)
  npeaks = length(peaks)
  if (!is.null(peaks) && n > 0 && npeaks > 0) { 
    if ((last(peaks) == n) || (last(peaks) == (n-1))) { return(TRUE) }
  }
  return(FALSE)
}

is_bottom = function(data,m=13) {
    data = na.omit(data)
    n = length(data)
    bottoms = find_peaks(-data,m=m)
    nbottoms = length(bottoms)
    if (!is.null(bottoms) && n > 0 && nbottoms > 0) {
      if ( (last(bottoms) == n) || (last(bottoms) == (n-1)) ) { return(TRUE) }
    }
    return(FALSE)
}


is_error = function(object) { 
  if (length(object) == 2) {
    code = object$code
    msg = object$msg
    if (!is.null(code) && !is.null(msg)) {
      return(TRUE)
    }
  }
  return(FALSE)
}
bearish_hammer = function(OHLC) { 
  if (!is.OHLC(OHLC)) { return(FALSE) }
  last_close = last(Op(OHLC))
  last_open = last(Cl(OHLC))
  last_high = last(Hi(OHLC))
  last_low = last(Lo(OHLC))
  
  min_price = min(last_close,last_open)
  max_price = max(last_open,last_close)
  
  dist_to_head_hi = last_high - max_price
  
  head_rsize = max_price - min_price

  min_to_head_ratio = (min_price - last_low) / head_rsize
  uppershadow_to_candle_ratio = dist_to_head_hi/head_rsize
  
  if (last_open < last_close) {

    if ( (min_to_head_ratio < 0.4) && (uppershadow_to_candle_ratio >= 0.6) ) { return(TRUE) }
    if (last_close < last_open) {
      ratio = (last_close - last_open)/(last_high - last_open)
      if (ratio < 0.5) { return(TRUE) }
    } 
    if (  ( ( abs( (last_close - last_high) / last_open ) < 0.005 ) ) && (uppershadow_to_candle_ratio < 0.3) ) { return(TRUE) }
  }
  return(FALSE)
}


bullish_hammer = function(OHLC) { 
  n = nrow(OHLC)
  last_close = last(Op(OHLC))
  last_open = last(Cl(OHLC))
  last_high = last(Hi(OHLC))
  last_low = last(Lo(OHLC))
  
  min_price = min(last_close,last_open)
  max_price = max(last_open,last_close)
  
  distance_to_head_hi = (last_high - max_price)/max_price
  
  dist_to_head_lo = min_price - last_low
  
  dist_to_head_hi = last_high - max_price
  
  head_rsize = max_price - min_price
  
  lowershadow_to_candle_ratio = dist_to_head_lo/head_rsize
  
  head_size = head_rsize/max_price
  
  max_to_head_ratio = (last_high-max_price)/head_rsize
  
  ##new code
  high_to_max = (last_high - max_price)/last_high
  max_to_min = (max_price - min_price)/max_price
  min_to_low = (min_price - last_low)/min_price
  #this measure is good for daily candles.
  
  if ( ((high_to_max < max_to_min) || almost_equal(high_to_max ,max_to_min,threshold=0.005)) && ((min_to_low > max_to_min) || almost_equal(min_to_low ,max_to_min,threshold=0.005) )) { return(TRUE) }
  
  ##
  if (all(almost_equal(last_close,last_high,threshold=0.005),last_open < last_close)) { return(TRUE) } 

  if (last_open < last_close) { 
    r1 = (last_close - last_open)/open
    r2 = (last_open - last_low)/last_low
    r3 = (last_high - last_close)/last_close
    if ((r1/r2 <= 0.5) && (r3 < r2)) { return(TRUE) }
    if ( (max_to_head_ratio < 0.4) && (lowershadow_to_candle_ratio >= 0.6) ) {
      return(TRUE)
    }
    ratio = (last_high - last_close)/(last_open - last_close) 
    if (ratio > 1.5) { return(TRUE) }
  }
  return(FALSE)
}

almost_equal = function(v1,v2,threshold = 0.0015) { 
  max_val = max(v1,v2)
  min_val = min(v1,v2)
  difference = (max_val - min_val)/max_val
  if (difference < threshold) { return(TRUE) }
  return(FALSE)
}

#Returns TRUE if the last candle shows a bearish hammer.
bearish_harami = function(OHLC) {
  
  if (!is.OHLC(OHLC)) { return(FALSE) }
  n = length(Cl(OHLC))
  if (n < 3) { return(FALSE) }
  
  last_close = last(Op(OHLC),2)
  last_open = last(Cl(OHLC),2)
  last_high = last(Hi(OHLC),2)
  last_low = last(Lo(OHLC),2)
  
  max_price = rep(0,2)
  
  max_price[1] = max(last_open[1],last_close[1])
  max_price[2] = max(last_open[2],last_close[2])
  
  min_price = rep(0,2)
  
  min_price[1] = min(last_open[1],last_close[1])
  min_price[2] = min(last_open[2],last_close[2])
  
  bull = (last_open[1] > last_close[1])
  
  #normal bearish harami
  if ( (max_price[1] >= max_price[2]) && (min_price[1] >= min_price[2]) && (isTRUE(bull))) { return(TRUE) }
  #green candle followed by a red candle biger
  if ( (last_open[1] < last_close[1]) && (last_close[1] > last_close[2]) && (last_open[1] > last_close[2])) { return(TRUE) }
  #green candle then a spike such that the highest point of the previous is bigger than the max of the next candle and the candle is red.
  if ( (last_open[1] < last_close[1]) && (last_high[1] > last_high[2]) && (last_close[2] < last_open[2]) ) { return(TRUE) }
  return(FALSE)
}
bullish_harami = function(OHLC) {
  if (!is.OHLC(OHLC)) { return(FALSE) }
  n = length(Cl(OHLC))
  if (n < 3) { return(FALSE) }
  last_close = last(Op(OHLC),2)
  last_open = last(Cl(OHLC),2)
  last_high = last(Hi(OHLC),2)
  last_low = last(Lo(OHLC),2)
  max_price = rep(0,2)
  max_price[1] = max(last_open[1],last_close[1])
  max_price[2] = max(last_open[2],last_close[2])
  min_price = rep(0,2)
  min_price[1] = min(last_open[1],last_close[1])
  min_price[2] = min(last_open[2],last_close[2])
  bear = (last_open[1] > last_close[1])
  if ( (max_price[1] > max_price[2]) && (min_price[1] > min_price[2]) && (isTRUE(bear)) ) { return(TRUE) }
  return(FALSE)
}

#is_candle_closed = function(pair="BTCUSDT",timeframe="1d",exchange="binanceus",data_in=NULL){
#  if (!is.null(data_in)) { 
#    candles = data_in
#  }
#  else {
#    pair = toupper(pair); exchange= tolower(exchange)
#    candles = pull_data(pair = pair, exchange=exchange,timeframe=timeframe,training_size = 2)
#  }
#  candle_time = last(candles[,1])
#  candle_time = as_datetime(candle_time)
#  exchange_time = exchange_time(exchange)
#  candle_time_numeric = as.numeric(candle_time)
#  exchange_time_numeric = as.numeric(exchange_time)
  
#  candles_interval = substrRight(timeframe,1)
#  candles_interval = tolower(candles_interval)
  
#  n_periods = as.numeric(substrLeft(timeframe,1))
#  actual_time = c(); last_candle_time = c()
  
#  print(candle_time)
#  #binance time object
#  actual_time$year = year(exchange_time)
#  actual_time$day = day(exchange_time)
#  actual_time$hour = hour(exchange_time)
#  actual_time$minute = minute(exchange_time)
#  actual_time$second = second(exchange_time)
  
#  #candle time object
#  last_candle_time$year = year(candle_time)
#  last_candle_time$day = day(candle_time)
#  last_candle_time$hour = hour(candle_time)
#  last_candle_time$minute = minute(candle_time)
#  last_candle_time$second = second(candle_time)

#  day_difference = actual_time$day - last_candle_time$day
#  hour_difference = actual_time$hour - last_candle_time$hour
#  minute_difference = actual_time$minute - last_candle_time$minute
  
#  if (candles_interval == "d") {
#    #TRUE if the daily candle closed within the last hour
#    if ( (day_difference == n_periods) && (actual_time$hour < 1) ) { return(TRUE) }
#  }
#  else if (candles_interval == "h") {
#    #TRUE if the hourly candle closed within the last minute.
#    if ( (hour_difference == n_periods) && (actual_time$minute < 1) ) { return(TRUE) }
#  }
#  else if (candles_interval == "m") {
#    #TRUE if the minute candle closed within the last 10 seconds.
#    print(minute_difference); print(n_periods); print(actual_time$second)
#    if ( (minute_difference == n_periods) && (actual_time$second <= 10) ) { return(TRUE) }
#  }
#  return(FALSE)
#}

is_candle_closed = function(pair="BTCUSDT",timeframe="1d",exchange="binanceus") {
  exchange_time = exchange_time("binance")
  exchange_time_numeric = as.numeric(exchange_time)
  
  candles_interval = substrRight(timeframe,1)
  candles_interval = tolower(candles_interval)
  
  n_periods = as.numeric(substrLeft(timeframe,1))
  actual_time = c(); last_candle_time = c()
  
  #binance time object
  actual_time$year = year(exchange_time)
  actual_time$day = day(exchange_time)
  actual_time$hour = hour(exchange_time)
  actual_time$minute = minute(exchange_time)
  actual_time$second = second(exchange_time)

  if (candles_interval == "1d") {
    #TRUE if the daily candle closed and no more than 10 minutes ago
    if (actual_time$minute < 10) { return(TRUE) }
  }
  else if (candles_interval == "h") {
    #TRUE if the hourly candle closed within the last minute.
    if ((actual_time$hour%%n_periods == 0) && (actual_time$minute < 1) ) { return(TRUE) }
  }
  else if (candles_interval == "m") {
    #TRUE if the minute candle closed within the last 10 seconds.
    if (n_periods >= 5) { delay = 60 }
    else if (n_periods < 5) { delay = 10 }
    if ( (actual_time$minute%%n_periods == 0) && (actual_time$second <= delay) ) { return(TRUE) }
  }
  return(FALSE)
} 

is_stablecoin = function(pair) { 
  base_currency_4 = substrRight(pair,4)
  base_currency_3 = substrRight(pair,3)
  base_currency_4 = toupper(base_currency_4)
  base_currency_3 = toupper(base_currency_3)
  stable_coins = c("DAI","PAX","BUSD","TUSD","GUSD","USDC","USDT")
  n = length(stable_coins[stable_coins==base_currency_3]) + length(stable_coins[stable_coins==base_currency_4])
  if (n > 0) { return(TRUE) }
  return(FALSE)
}

#maximum delay was 8 seconds in 1 minute candle

#testing the delay with the server
#while(1) {
#  closed = is_candle_closed(data_in=data,timeframe="1m")
#  Sys.sleep(2);
#  data = pull_data(timeframe="1m")
#  if (isTRUE(closed)) { time = binance_time(); print(time); }
#}

#Returns TRUE if the last candle shows a bearish hammer
