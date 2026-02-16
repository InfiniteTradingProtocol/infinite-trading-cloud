#################################################
#### File: basic.R    ###########################
#### Author: R. Clare ###########################
####                  ###########################
#### Description      ###########################
####                  ###########################n
#### This file includes all basic functions #####
#### that are used by most of the other files ###
#################################################

# wd should be set by parent script - don't override it
if (!exists("wd")) { wd = "~/infinitetrading/src/" }
publicSleepInterval = 0.1

install_load <- function (package1, ...)  {
  
  # convert arguments to vector
  packages <- c(package1, ...)
  
  # start loop to determine if each package is installed
  for(package in packages){
    
    # if package is installed locally, load
    if(package %in% rownames(installed.packages()))
      do.call('library', list(package))
    
    # if package is not installed locally, download, then load
    else {
      install.packages(package)
      do.call("library", list(package))
    }
  }
}

#install_load("rgdax","webshot","slackr","nortest","rlang","quantmod","logger","TTR","forecast","Xmisc","data.table","stringr","digest","httr","lubridate","snakecase","plotly","keras")

reference = function(package) {
  for (i in 1:length(package)) { source(paste(wd,package[i],sep="")) }
}

reference(c("exchanges/api.R","slack.R","boolean.R","db.R"))

range01 <- function(x){(x-min(x))/(max(x)-min(x))}

ma_differences = function(data,maType="EMA",fast=47,slow=97,normalize=TRUE) { 
  if (maType == "EMA") { differences = EMA(data,n = slow) - EMA(data,n = fast) }
  else if (maType == "SMA") { differences = SMA(data,n = slow) - SMA(data,n = fast) }
  if (normalize) {
    mini = min(differences)
    maxi = max(differences)
    differences = (differences - mini)/(maxi-mini) 
  }
  return(differences)
}

hi_lo_differences = function(OHLC,periods=7,ma=FALSE,maType="SMA",ma_periods=3) { 
  values = c()
  hi = Hi(OHLC)
  low = Lo(OHLC)
  close = Cl(OHLC)
  values[1:(periods - 1)] = 0
  for (i in periods:nrow(OHLC)) {
    last_val = (i - periods + 1):i
    maxi = max(hi[last_val])
    mini = min(low[last_val])
    values[i] = (maxi - close[i])/(maxi - mini)
  }
  if (ma) { 
    if (maType == "SMA") { values = SMA(values,ma_periods) }
    else if (maType == "EMA") { values = EMA(values,ma_periods) }
  }
  return(values)
}
heikin_ashi = function(OHLC,type="mean",chart=FALSE) {
	close = Cl(OHLC)
        open = Op(OHLC)
	low = Lo(OHLC)
	high = Hi(OHLC)
	n = nrow(OHLC)
	if (type=="mean") { heikin_close = (open+close+low+high)/4 }
	else if (type == "median") {
		heikin_close= rep(0,n)
		for (i in 1:n) { heikin_close[i] = median(open[i],close[i],low[i],high[i]) }
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


HLC = function(OHLC) { 
  return(cbind(OHLC[,1],OHLC[,3],OHLC[,2],OHLC[,5]))  
}
HL = function(OHLC) { 
  return(cbind(OHLC[,3],OHLC[,2]))  
}
get_priceType = function(candles,priceType = "close") { 
  if (is.OHLC(candles)) { 
    close = Cl(candles)
    high = Hi(candles)
    low = Lo(candles)
    open = Op(candles)
  }
  else { return(candles) }
  n = length(close)
  if (!any(priceType==c("close","c","open","o","ohlc4","hl2","high","h","l","low","med","hlc3"))) { priceType = "close" }
  if (priceType == "close" || priceType=="c") { return(close) }
  else if (priceType== "high" || priceType == "h") { return(high) }
  else if (priceType== "o" || priceType == "open") { return(open) }
  else if (priceType== "l" || priceType == "low") { return(low) }
  else if (priceType == "median") { }
  else if (priceType == "hlc3") { return((high+low+close)/3)}
  else if (priceType == "ohlc4") { return((high+low+close+open)/4)}
  else if (priceType == "hl2") { return((high+low)/2)}
  else if (priceType == "med") {
    median_prices = rep(0,n)
    for (i in 1:n) { 
      median_prices[i] = median(c(open[i],close[i],high[i],low[i]))
    }
    return(median_prices)
  }
}
#Instructions:
#Clone this repo
#Copy and paste all of this code into R

#Put here your working directory


#All of the repo code will be loaded automatically after doing this.


substrRight <- function(x, n){
  substr(x, nchar(x)-n+1, nchar(x))
}
substrLeft <- function(x, n){
  substr(x,1,nchar(x) - n)
}

##########
#Easy loading of the R files or "packages"
##########


#avoid scientific notation for BTC pairs.
options(scipen=999)


load_api = function() {
  reference("exchanges/api.R")
  dir_list = list.dirs(path=wd,full.names=FALSE)
  dir_list = dir_list[-1]
  n = length(dir_list)
  dir_list = paste(dir_list,rep("/",n),sep="")
  for (dir in dir_list) {
    sub_path = paste(wd,dir,sep="")
    file_list = list.files(path=sub_path, pattern=".R",include.dirs = FALSE)
    for (file in file_list) {
      file_t = file
      file = paste(sub_path, file, sep='')
      if (is.file(file)) {
        if ((file_t != "basic.R") && (substrRight(file_t,2) == ".R")) { cat("Loading: ", file, "\n"); source(file);  }
      }
    }
  }
}

#this call is loading all of the .R files on the working directory
#load_all_files()

#######################################
## Function: get_price            #####
## Output: OHLCV                  #####
##                                #####
## Parameters                     #####
## pair : BTC-USD                 #####
## timeframe:                     #####
## "1m","5m","15m","1h","6h","1d" #####
##                                #####
## Description:                   #####
## Extracts data from coinbase    #####
#######################################

get_price = function(pair,timeframe,samples = 500) {
  return (public_candles(pair,granularity =tf(timeframe)))
}

stocks_candles = function(pair="AMZN",timeframe="1h",source ='yahoo') {
  symbols = getSymbols(pair,from="2018-06-01",to="2019-06-01",src=source,return.class='ts')
  assetPrice = get(symbols)
  assetPrice = cbind(time(assetPrice),assetPrice[,3],assetPrice[,2],assetPrice[,1],assetPrice[,4],assetPrice[,5])
  colnames(assetPrice) <- c("Time","Low","High ","Open","Close ","Volume ")
  rownames(assetPrice) <- NULL
  return(assetPrice)
}

dollars = c("USDT","USD","PAX","USDC","TUSD","GUSD","DAI")

########################################
## Function: get_index()           #####
## Parameter: vector               #####
## Description:                    #####
##  Returns the index of the first #####
##  nonempty element in the vector #####
########################################

get_index = function(vector = NULL) {
  n = length(vector);
  for (i in 1:n) { if (!is.na(vector[i])) { return(i) } }
}

currency_symbol = function(base_currency) {
  base_currency = toupper(base_currency)
  if (base_currency == "BTC" || base_currency == "BITCOIN") { return("B") }
  else if (base_currency == "USD" || base_currency=="DOLLAR") { return("$") }
  else { return("") }
}

#List of most used base currencies
base_currencies = c("BTC","USD","USDT","GUSD","DAI","PAX","ETH","BNB","DOGE","XRP","XLM","GUSD","TUSD","USDC")

currencies = c("GRT","LDO","ATOM","OP","ORN","ADA","SOL","UNI","AAVE","CRV","MATIC","DOT","BTC","LTC","ETC","EOS","ICP","ICX","LINK","USD","USDT","GUSD","DAI","PAX","ETH","BNB","DOGE","XRP","XLM","GUSD","TUSD","ZRX","THETA","RVN","IOTA","XTZ")


#Extract the base currency from a price in any format.

get_base_currency = function(pair="BTC-USD") {
  pair = toupper(pair)
  last_3 = substrRight(pair,3)
  last_4 = substrRight(pair,4)
  count1 = length(which(base_currencies == last_3))
  count2 = length(which(base_currencies == last_4))
  if (count1 > 0) { return(last_3) }
  else if (count2 > 0) { return(last_4) }
  print("Error: unknown base currency")
}


#mejorar esto usando la funcion que divide por -  los nombres si los tiene
#Si tiene un - dividelo en dos, si no, usa el approach viejo.
get_trade_currency = function(pair="BTC-USD") {
  pair = toupper(pair)
  first_3 = substrLeft(pair,3)
  first_4 = substrLeft(pair,4)
  first_5 = substrLeft(pair,5)
  count1 = length(which(currencies == first_3))
  count2 = length(which(currencies == first_4))
  count3 = length(which(currencies == first_5))
  if (count1 > 0) { return(first_3) }
  else if (count2 > 0) { return(first_4) }
  else if (count3 >0) { return(first_5) }
  print("Error: unknown currency")
}

base_price = function(assetPrice,assetAmount) {
  return(assetPrice*assetAmount)
}
date_sequence = function(timeframe="1d",h=20,as_datetime=FALSE) {
  timeframe_periods = as.numeric(substrLeft(timeframe,1))
  timeframe_units = substrRight(timeframe,1)
  horizon = timeframe_periods*1:h
  future_dates = switch(timeframe_units,w = weeks(horizon), d = days(horizon),h = hours(horizon),m = minutes(horizon))
  if (isTRUE(as_datetime)) { future_dates = as_datetime(future_dates) }
  return(future_dates)
}


#returns the decimal places of a number.
decimalplaces = function(x) {
  if (abs(x - round(x)) > .Machine$double.eps^0.5) {
    nchar(strsplit(sub('0+$', '', as.character(x)), ".", fixed = TRUE)[[1]][[2]])
  } else {
    return(0)
  }
}

#completar esta function para visualizar y tradear los width de los BBands
#crear una estrategia con esto
#Bollinger bands width

which_is_max = function(v1,v2) {
  n = length(v1); max = v1[1];
  if (n == length(v2)) {
    for (i in 1:n) {
        if (v1[1] < v2[i]) { max = v2[i] }
        else { max = v1[i] }
    }
    return(max)
  }
  else { print("Error: both vectors needs to be of the same size") }
}
first_index = function(vector) {
  index = 1; n = length(vector)
  for (i in 1:n) {
    if (!is.na(vector[i])) { break }
    else { index = index + 1  }
  }
  return(index);
}

center_price = function(assetPrice) {
  centerprice = (Hi(assetPrice) + Lo(assetPrice) + Cl(assetPrice))/3
  return (centerprice)
}

nRSI = function(OHLC,periods=c(7,50)) { 
  require(TTR)
  require(quantmod)
  RSI(RSI(Cl(OHLC),n=periods[2]),n=periods[1])
}

max_values = function(v1,v2) {
  n = length(v1); r = rep(0,n)
  for (i in 1:n) {
      r[i] = max(v1[i],v2[i])
  }
  return (r)
}

min_values = function(v1,v2) {
  n = length(v1); r = rep(0,n)
  for (i in 1:n) {
    r[i] = min(v1[i],v2[i])
  }
  return (r)
}

tf = function(g) {
  tf = substrRight(g,1)
  r = as.numeric(substrLeft(g,1))
  if (tf == "m") { return(60*r) }
  else if (tf == "h" || tf == "H") { return (3600*r) }
  else if (tf == "d" || tf == "D") { return(86400*r) }
  else if (tf == "w" || tf == "W") { return(604800*r) }
  else if (tf == "M") { return(2419200*r) }
  else { return(g); }
}

last_n_trend = function(prices,n=7) {
  n = min(n,length(prices))
  if (n < 2) { return(0) }
  x = 1:n
  linear_regression = lm(x~last(prices,n))
  slope = as.numeric(linear_regression$coefficients[2])
  return(slope)
}
info_series = function(prices,n=7) {
  k = length(prices)
  info = rep(0,length(prices))
  for (i in n:k) {
    info[i] = last_n_trend(prices[1:i],n=n)
  }
  return(info)
}
padjust = function(price,decimals) {
  return(floor(price*10^(decimals))/10^(decimals))
}
load_models = function(models) {
  reference(c("ml/ml_indicators.R","ml/ml_indicators_matrix.R","ml/backtesting.R"))
  #source_python(path.expand(paste0(wd,'sendInstruction.py')))
  require(quantmod); require(TTR); require(httr); require(rgdax); require(jsonlite); require(lubridate); require(snakecase); require(reticulate); reference("slack.R"); require(keras);
  for (i in 1:length(models)) { 
    model = paste(models[i],".hdf5",sep="")
    cat("Loading model: ",model,"\n")
    keras_object = load_model_hdf5(paste(wd,"/models/",model,sep=""), custom_objects = NULL, compile = TRUE)
    model_object = c()
    model_object = readRDS(file = paste(wd,"/models/",models[i],".rds",sep=""))
    model_object$model = keras_object
    assign(models[i],model_object, envir = .GlobalEnv)
  }
}
