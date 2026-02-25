#############################################
## Function: pull_data()                #####
## Output: OHLCV                        #####
##                                      #####
## Description:                         #####
##  Returns an OHLCV for the specified  #####
##  pair,timeframe and exchange.        #####  
#############################################

source("~/infinitetrading/src/db.R")
#source("/home/ubuntu/infinitetrading/db/candles_mysql.R")
require(quantmod)
require(lubridate)

pull_data = function(pair="BTCUSDT",timeframe="1d",exchange="Binance",data_in=NULL,source=NULL,training_size = 500,redis=FALSE,mysql=FALSE) {
  pair = toupper(pair); exchange = tolower(exchange)
  n = length(pair)
  if (!is.null(data_in)) {
    candles = data_in
  }
  else if (isTRUE(redis)) {
    if (exchange == "binance") { candles = binance_get_candles_redis(pair=pair,timeframe=timeframe,samples = training_size) } 
    else if (exchange == "coinbase") { candles = coinbase_get_candles_redis(pair = pair,timeframe = timeframe,samples = training_size) }
    else if (exchange == "stocks") { candles = stocks_candles_redis(pair="AMZN",timeframe="1d",source='yahoo') }
  }
  else if (isTRUE(mysql)) { 
  	candles = pull_candles(pair,timeframe,exchange)
  }
  else if (n == 1) {
    if (exchange == "binance") { candles = binance_get_candles(pair=pair,timeframe=timeframe,samples = training_size) } 
    else if (exchange == "coinbase") { candles = coinbase_get_candles(pair = pair,timeframe = timeframe,samples = training_size) }
    else if (exchange == "stocks") { candles = stocks_candles(pair="AMZN",timeframe="1d",source='yahoo') }
  }
  else { return(0); }
  #multiple exchanges/pairs
  #incomplete
  #else if (n > 1) {
  #  for (i in 1:n) { }
  #}
  if (!mysql) { push_candles(candles,pair=pair,timeframe=timeframe,exchange=exchange) }
  return(candles)
}

