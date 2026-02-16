library(rgdax)
library(lubridate)

realSleep <-function(numSeconds=1)
{
  startTime <- Sys.time()
  currentTime <- startTime
  sleepUntil <- startTime + seconds(numSeconds)
  while(currentTime < sleepUntil)
  {
    # print(paste("The current time is: ", currentTime, sep=""))
    # print(paste("Going to sleep until: ", sleepUntil, sep=""))
    # print(paste("Will sleep for: ", as.numeric(sleepUntil - currentTime), sep=""))
    Sys.sleep(as.numeric(sleepUntil - currentTime))
    # print(paste("Woke up at: ", Sys.time(), sep=""))
    #Sys.sleep(publicSleepInterval)
    currentTime <- Sys.time()
    #print(paste("Should I still be asleep?", currentTime < sleepUntil, sep=""))
  }
}


getDailyCryptoCurrencyData <- function(pair, numDays=599)
{ 
  dailyPrices <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 86400)
  
  if (numDays > 300)
  {
    for(currentIndex in seq(300, numDays, by = 300))
    {
      realSleep(publicSleepInterval)
      endDate <- format(head(dailyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(dailyPrices$time, 1) - days(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      
      dailyPrices <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 86400), dailyPrices)
    }    
  }
  
  tail(dailyPrices, numDays)
}

getHourlyCryptoCurrencyData <- function(pair, numHours)
{ 
  #Load data from GDAX; each request can pull up to 300 data points
  #Can loop over requests to obtain more, by varying the start and end date, using ISO 8601 date format
  
  hourlyPrices <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 3600)
  realSleep(publicSleepInterval)
  if (numHours > 300)
  {
    for(currentIndex in seq(300, numHours, by = 300))
    {
      realSleep(publicSleepInterval)
      endDate <- format(head(hourlyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(hourlyPrices$time, 1) - hours(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      
      hourlyPrices <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 3600), hourlyPrices)
      realSleep(publicSleepInterval)
    }    
  }
  
  tail(hourlyPrices, numHours)
}

#getHourlyCryptoCurrencyData("ETH-USD", 16000)

getSixHourCryptoCurrencyData <- function(pair, numPeriods)
{ 
  #pair = "ETH-USD"
  #numPeriods = 6000
  #Load data from GDAX; each request can pull up to 300 data points; can loop over requests to obtain more, by varying the start and end date, using ISO 8601 date format
  
  print(paste("The sleep interval is:", publicSleepInterval, sep = ""))
  
  hourlyPrices <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 21600)
  
  if (numPeriods > 300)
  {
    for(currentIndex in seq(300, numPeriods, by = 300))
    {
      realSleep(publicSleepInterval)
      #There's a bug in here, when the hour is 00:00:00
      #py$time.sleep(sleepInterval)
      endDate <- format(head(hourlyPrices$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(hourlyPrices$time, 1) - hours((300*6)), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      
      hourlyPrices <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 21600), hourlyPrices)
      
      #if (currentIndex %% 600 == 0)
      #{
      #}
    }    
  }
  
  tail(hourlyPrices, numPeriods)
}

getLatestCurrencyDataByMinute <- function(pair, intervalSize)
{
  public_candles(product_id = pair, start = parse_date_time(floor_date(now("UTC"), unit="minutes"), "ymd HMS") - minutes(intervalSize), end = parse_date_time(floor_date(now("UTC"), unit="minutes"), "ymd HMS"), granularity = 60)
}

getCryptoCurrencyDataByMinute <- function(pair, numMinutes)
{ 
  pricesByMinute <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 60)
  
  realSleep(publicSleepInterval)
  if (numMinutes > 300)
  {
    for(currentIndex in seq(300, numMinutes, by = 300))
    {
      realSleep(publicSleepInterval)
      endDate <- parse_date_time(head(pricesByMinute$time, 1), "ymd HMS")
      startDate <- parse_date_time(head(pricesByMinute$time, 1), "ymd HMS") - minutes(300)
      
      endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(pricesByMinute$time, 1) - minutes(300), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      
      pricesByMinute <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 60), pricesByMinute)
      realSleep(publicSleepInterval)
    }    
  }
  
  #pricesByMinute
  tail(pricesByMinute, numMinutes)
}

getFiveMinuteCryptoCurrencyData <- function(pair, numMinutes)
{ 
  pricesByMinute <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 300)
  
  realSleep(publicSleepInterval)
  if(numMinutes > 300)
  {
    for(currentIndex in seq(300, numMinutes, by = 300))
    {
      realSleep(publicSleepInterval)
      
      endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
      startDate <- format(head(pricesByMinute$time, 1) - minutes(300*5), tz="GMT", format="%Y-%m-%d %H:%M:%S")
      
      pricesByMinute <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 300), pricesByMinute)
      
      realSleep(publicSleepInterval)
    }
  }
  
  tail(pricesByMinute, numMinutes)
}

getFifteenMinuteCryptoCurrencyData <- function(pair, numMinutes)
{ 
  pricesByMinute <- public_candles(product_id = pair, start = NULL, end = NULL, granularity = 900)
  
  for(currentIndex in seq(300, numMinutes, by = 300))
  {
    realSleep(publicSleepInterval)
    
    endDate <- format(head(pricesByMinute$time, 1), tz="GMT", format="%Y-%m-%d %H:%M:%S") 
    startDate <- format(head(pricesByMinute$time, 1) - minutes(300*15), tz="GMT", format="%Y-%m-%d %H:%M:%S")
    
    pricesByMinute <- rbind(public_candles(product_id = pair, start = startDate, end = endDate, granularity = 900), pricesByMinute)
  }
  
  tail(pricesByMinute, numMinutes)
}

getCoinbaseData <-function(symbol, minuteInterval, numSamples)
{
  if (minuteInterval == 1440)
  {
    currencyData <- getDailyCryptoCurrencyData(symbol, numSamples)
  }
  else if (minuteInterval == 60)
  {
    currencyData <- getHourlyCryptoCurrencyData(symbol, numSamples)
  }
  else if (minuteInterval == 360)
  {
    currencyData <- getSixHourCryptoCurrencyData(symbol, numSamples)
  }
  else if (minuteInterval == 1)
  {
    currencyData <- getCryptoCurrencyDataByMinute(symbol, numSamples)
  }
  else if (minuteInterval == 5)
  {
    currencyData <- getFiveMinuteCryptoCurrencyData(symbol, numSamples)
  }
  else if (minuteInterval == 15)
  {
    currencyData <- getFifteenMinuteCryptoCurrencyData(symbol, numSamples)
  }
  
  currencyData <- na.omit(currencyData)
}
#End code authored by Angel Aponte
