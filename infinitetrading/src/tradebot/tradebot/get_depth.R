#This function obtains the orderbook info
#from the specified exchange

get_depth = function(pair="BTCUSDT",exchange="binanceus",level=3,limit=500,data_in=NULL) {
  
  pair = toupper(pair); exchange=tolower(exchange)
  if (!is.null(data_in)) { return(data_in) }
  
  if (exchange == "coinbase") {
    depth = public_orderbook(product_id = pair, level = level)
  }
  else if (exchange == "binance" || exchange == "binanceus") {
    depth = binance_depth(symbol = pair,limit = limit,as_vector=TRUE)
  }
  return(depth)
}