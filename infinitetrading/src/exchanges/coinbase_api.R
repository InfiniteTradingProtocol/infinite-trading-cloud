#Copyright Angel Aponte
#Author: Angel Aponte
#Modified: Richard Clare
#Description: Functions used to invoke the Coinbase Pro API through the rgdax package.

#For internal Tradery use only. Removal of copyright and authorship, legal disclaimer,
#unauthorized copying, reproduction, or other use outside of Tradery is prohibited.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

require(rgdax); require(lubridate); require(jsonlite)
coinbase_get_candles = function(pair='BTC-USD',timeframe='1d',samples = 500) {
  if (timeframe == "1d") { data = getDailyCryptoCurrencyData(pair,numDays=samples) }
  else if (timeframe == "5m") { data = getFiveMinuteCryptoCurrencyData(pair,numMinutes = samples) }
  else if (timeframe == "1m") { data = getOneMinuteCryptoCurrencyData(pair,numDays= samples) }
  else if (timeframe == "6h") { data = getSixHourCryptoCurrencyData(pair,numPeriods=samples) }
  else if (timeframe == "1h") { data =getHourlyCryptoCurrencyData(pair,numHours=samples) }
  else if (timeframe == "15m") { data = getFifteenMinuteCryptoCurrencyData(pair,numMinutes = samples) }
  return(data)
}
#public_candles_new = function(product_id = "LTC-USD", start = NULL, end = NULL,granularity = NULL) {
# 	prices = invisible(public_candles(product_id = product_id, start = start, end = end, granularity = granularity))
#	data = fromJSON(content(prices,as="text"))
#	data = as.data.frame(data)
#	data$V1 <- as.numeric(data$V1)
#	data <- data[order(data$V1,decreasing=FALSE), ]
#	names(data) <- c("time", "low", "high","open", "close", "volume")
#	data$time <- as.POSIXct(data$time, origin = "1970-01-01",tz = "GMT")
#	return(invisible(data))
#}

public_candles_new = function(product_id = "LTC-USD", start = NULL, end = NULL, granularity = NULL) {
	OHLC =tryCatch({
		prices = public_candles(product_id = product_id, start = start, end = end, granularity = granularity)
		data = fromJSON(rawToChar(prices$content))
		#if (is.character(content(prices, as = "text"))) {
    		#	data = fromJSON(content(prices, as = "text"))
		#} else { stop("Invalid content returned from public_candles") }
        	# Rename columns
        	data = as.data.frame(data)
		data <- data[order(data$V1,decreasing=FALSE), ]
		colnames(data) <- c("time", "low", "high", "open", "close", "volume")
		# Convert 'time' to POSIXct format
		data$time <- as.POSIXct(data$time, origin = "1970-01-01", tz = "GMT")
		print(data$time)
		data
		},
		error = function(e) { print(paste0("Error using public_candles_new: ", e$message)); NULL })
	return(OHLC)
}
publicSleepInterval = 0.1
#Angel aponte code starts here
realSleep <-function(numSeconds=1) {
  startTime <- Sys.time(); currentTime <- startTime;sleepUntil <- startTime + seconds(numSeconds)
  while(currentTime < sleepUntil) {
    Sys.sleep(as.numeric(sleepUntil - currentTime))
    currentTime <- Sys.time()
   }
}
getDailyCryptoCurrencyData <- function(pair, numDays) { 
  dailyPrices = public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 86400)
  if (numDays > 300) {
    for(currentIndex in seq(300, numDays, by = 300)) {
      realSleep(publicSleepInterval)
      endDate <- format(head(dailyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(dailyPrices$time, 1) - days(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      newdailyPrices = public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 86400)
      dailyPrices <- rbind(newdailyPrices,dailyPrices)
    }    
  }
  return(tail(dailyPrices, numDays))
}

getOneMinuteCryptoCurrencyData <- function(pair, numDays) {
	dailyPrices <- public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 60)
  	if (numDays > 300) {
		for(currentIndex in seq(300, numDays, by = 300)) {
			realSleep(publicSleepInterval)
        		endDate <- format(head(dailyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S")
	      		startDate <- format(head(dailyPrices$time, 1) - minutes(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
	      		dailyPrices <- rbind(public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 60), dailyPrices)
	          }
    	}
    	return(tail(dailyPrices, numDays))
}
getHourlyCryptoCurrencyData <- function(pair, numHours,start=NULL,end=NULL) { 
  hourlyPrices <- public_candles_new(product_id = pair, start = start, end = end, granularity = 3600)
  realSleep(publicSleepInterval)
  if (numHours > 300) {
    for(currentIndex in seq(300, numHours, by = 300)) {
      realSleep(publicSleepInterval)
      endDate <- format(head(hourlyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(hourlyPrices$time, 1) - hours(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      newhourlyPrices = public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 3600) 
      hourlyPrices <- rbind(newhourlyPrices, hourlyPrices)
      realSleep(publicSleepInterval)
    }    
  }
  return(tail(hourlyPrices, numHours))
}
getSixHourCryptoCurrencyData <- function(pair, numPeriods) { 
  print(paste("The sleep interval is:", publicSleepInterval, sep = ""))
  hourlyPrices <- public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 21600)
  if (numPeriods > 300)
  {
    for(currentIndex in seq(300, numPeriods, by = 300)) {
      realSleep(publicSleepInterval)
      #There's a bug in here, when the hour is 00:00:00
      #py$time.sleep(sleepInterval)
      endDate <- format(head(hourlyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(hourlyPrices$time, 1) - hours((300*6)), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      newhourlyPrices = public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 21600)
      hourlyPrices <- rbind(newhourlyPrices, hourlyPrices)
    }    
  }
  return(tail(hourlyPrices, numPeriods))
}
getLatestCurrencyDataByMinute <- function(pair, intervalSize) { public_candles_new(product_id = pair, start = parse_date_time(floor_date(now("UTC"), unit="minutes"), "ymd HMS") - minutes(intervalSize), end = parse_date_time(floor_date(now("UTC"), unit="minutes"), "ymd HMS"), granularity = 60) }
getCryptoCurrencyDataByMinute <- function(pair, numMinutes) { 
  pricesByMinute <- public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 60)
  realSleep(publicSleepInterval)
  if (numMinutes > 300) {
    for(currentIndex in seq(300, numMinutes, by = 300)) {
      realSleep(publicSleepInterval)     
      endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(pricesByMinute$time, 1) - minutes(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      pricesByMinute <- rbind(public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 60), pricesByMinute)
      realSleep(publicSleepInterval)
    }    
  }
  return(tail(pricesByMinute, numMinutes))
}

getFiveMinuteCryptoCurrencyData <- function(pair, numMinutes) { 
  pricesByMinute <- public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 300)
  realSleep(publicSleepInterval)
  if(numMinutes > 300) {
    for(currentIndex in seq(300, numMinutes, by = 300)) {
      realSleep(publicSleepInterval)
      endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(pricesByMinute$time, 1) - minutes(300*5), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      pricesByMinute <- rbind(public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 300), pricesByMinute)
      realSleep(publicSleepInterval)
    }
  }
  return(tail(pricesByMinute, numMinutes))
}
getFifteenMinuteCryptoCurrencyData <- function(pair, numMinutes) { 
  pricesByMinute <- public_candles_new(product_id = pair, start = NULL, end = NULL, granularity = 900) 
  for(currentIndex in seq(300, numMinutes, by = 300)) {
    realSleep(publicSleepInterval)
    endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
    startDate <- format(head(pricesByMinute$time, 1) - minutes(300*15), tz="GMT", format="%Y-%m-%d %H:%M:%S")
    pricesByMinute <- rbind(public_candles_new(product_id = pair, start = startDate, end = endDate, granularity = 900), pricesByMinute)
  }
  return(tail(pricesByMinute, numMinutes))
}
#End code authored by Angel Aponte
#coinbase_get_candles(pair='BTC-USD',timeframe='6h',samples = 300) 
