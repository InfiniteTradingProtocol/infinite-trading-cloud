require(httr)
require(jsonlite)
require(PerformanceAnalytics)
require(quantmod)
require(xts)
require(lubridate)
require(redux)

# Initialize Redis connection for rate limiting
redis <- redux::hiredis()

# Redis-based rate limiting functions
get_last_report_time <- function(key) {
  tryCatch({
    value <- redis$GET(key)
    if (is.null(value)) return(NULL)
    return(as.POSIXct(as.numeric(value), origin="1970-01-01"))
  }, error = function(e) {
    cat("Redis error in get_last_report_time:", e$message, "\n")
    return(NULL)
  })
}

update_last_report_time <- function(key) {
  tryCatch({
    # Store timestamp and set TTL to 1 hour (3600 seconds)
    redis$SETEX(key, 3600, as.numeric(Sys.time()))
  }, error = function(e) {
    cat("Redis error in update_last_report_time:", e$message, "\n")
  })
}

# Telegram is the only notification transport. Sourced defensively because the
# callers of this file source it inconsistently and discord() below depends on
# send_telegram_text being defined.
if (!exists("send_telegram_text")) source("~/infinitetrading/src/telegram.R")

# NOTIFICATIONS: retargeted to Telegram; Discord was retired and its webhooks
# removed. The name is kept so existing callers in this file keep working, and
# `channel` is used as a tag so the alert's origin stays visible.
discord = function(msg,channel="#market-overview") {
        tryCatch({
                send_telegram_text(paste0("[", channel, "] ", msg))
        }, error = function(e) {
                print(paste0("Failed to send message: ", conditionMessage(e)))
        })
}
require(jsonlite)
require(PerformanceAnalytics)
require(quantmod)
require(xts)
require(lubridate)

ds_price = function(pair,network,exchange,native=FALSE,pricechange=FALSE,liquidity=FALSE) {
  url <- "https://api.dexscreener.com/latest/dex/pairs/"
  ep = NULL; c= NULL
  if (network == "optimism") { ep = "optimism/" }
  else if (network == "polygon") { ep = "polygon/" }
  else if (network == "base") { ep = "base/" }
  if (exchange == "velodromeV2") {
        if (pair == "ITP-USDC") { c = "0xb84c932059a49e82c2c1bb96e29d59ec921998be" }
        else if (pair == "ITP-wstETH") { c = "0xdad7b4c48b5b0be1159c674226be19038814ebf6" }
        else if (pair == "ITP-WBTC")  { c = "0x93e40c357c4dc57b5d2b9198a94da2bd1c2e89ca" }
        else if (pair == "ITP-DHT") { c = "0x3d5cbc66c366a51975918a132b1809c34d5c6fa2" }
        else if (pair == "ITP-xOpenX") { c = "0x44fb5dc428c65576d5fce5298cf1c77ea28cf2dc" }
        else if (pair == "ITP-VELO") { c = "0xc04754f8027abbfe9eea492c9cc78b669646a07d1" }
        else if (pair == "ITP-OP") { c = "0x79f1af622fe2c636a2d946f03a62d1dfc8ca6de4" }
        else if (pair == "ITP-MAI") { c = "0x1ec3d6b917fbb4bf8536b683fb054b0ab1ff587a" }
        else if (pair == "alETH-WETH") { c = "0xa1055762336f92b4b8d2edc032a0ce45ead6280a" }
        else if (pair == "opxVELO-VELO") { c= "0xa80ad5c1f8c21b34b427ea432530ae7ff36e3926" }
        else if (pair == "frxETH-WETH") { c = "0x3f42dc59dc4df5cd607163bc620168f7ff7ab970" }
        else if (pair == "alUSD-USDC") { c = "0x4d7959d17b9710be87e3657e69d949691421bb88" }
        else if (pair == "sUSD-USDC") { c = "0x252cbdff917169775be2b552ec9f6781af95e7f6" }
        else if (pair == "MTA-USDC") { c = "0x8453cc52f2108ff9d1636b6a108db06ac137b72f" }
        else if (pair == "LUSD-USDC") { c = "0xf04458f7b21265b80fc340de7ee598e24485c5bb" }
        else if (pair == "tBTC-WBTC") { c = "0xe612cb2b5644aef0ad3e922bae70a8374c63515f" }
        ep = paste0(ep,c)
  }
  else if (exchange == "uniswapV3") { 
        if (network == "polygon") { 
                if (pair == "stMATIC-MaticX") ep = paste0(ep,"0xc63123aec88f6965d2792e96f9e8a3324dbbc6b0")
                }
        else if (network == "base") { 
                if (pair == "cbEGGS-cbETH") { ep = paste0(ep,"0x89129db57374fdad1e79a3c081d83f670d011925") }
                else if (pair == "cbETH-WETH") { ep = paste0(ep,"0x47ca96ea59c13f72745928887f84c9f52c3d7348") }
                }
  }
  url = paste0(url,ep)
  response <- GET(url)
  print(paste0("querying: ",url))
  if (response$status_code == 200) {
    # Parse JSON response
    data <- fromJSON(content(response, "text"))
    print(data)
    # Extract priceUsd value
    if (pricechange) {
            pricechange = c(as.numeric(data$pair$priceChange$m5),as.numeric(data$pair$priceChange$h1),as.numeric(data$pair$priceChange$h6),as.numeric(data$pair$priceChange$h24))
            #pricechange = data$pair$priceChange
            #pricechange = as.vector(pricechange)
            #pricechange[1] = as.numeric(pricechange[1])
            #pricechange[2] = as.numeric(pricechange[2])
            #pricechange[3] = as.numeric(pricechange[3])
            #pricechange[4] = as.numeric(pricechange[4])
            if (!native) { 
                #pricechange[5] = as.numeric(data$pairs$priceUsd)
                pricechange = c(as.numeric(data$pairs$priceUsd),pricechange)
            }
            else { 
                    #pricechange[5] = data$pairs$priceNative
                    pricechange = c(as.numeric(data$pairs$priceNative),pricechange)
                    }
            print(pricechange)
            return(pricechange)
    }
    else if (liquidity) { 
            data$pair$liquidity$price = as.numeric(data$pairs$priceUsd)
            return(data$pair$liquidity) 
    }
    else if (!native) { return(as.numeric(data$pairs$priceUsd)) }
    else { return(data$pairs$priceNative) }
  } else {
    cat("Error:", http_status(response)$reason, "\n")
    return(NULL)
  }
}

report = function(pair,price,type,channel="#price-alerts",pricechange=NULL) {
        # Redis-based rate limiting: max 1 alert per hour per pair+type combination
        redis_key <- paste0("price_alert:", pair, ":", type)
        last_report_time <- get_last_report_time(redis_key)
        
        mesg = ""
        if (!is.null(pricechange)) { 
                mesg = paste0(" changes: (5m: ",pricechange[2],"%) (1h: ",pricechange[3],"%) (h6: ",pricechange[4],"%) (1d: ",pricechange[5],"%)")
        }
        
        # Check if we should send the alert (more than 1 hour since last alert)
        current_hour <- hour(Sys.time())
        should_send <- FALSE
        
        if (is.null(last_report_time)) {
                # Never sent before, send now
                should_send <- TRUE
        } else {
                # Check if at least 1 hour has passed
                last_hour <- hour(last_report_time)
                if (current_hour != last_hour) {
                        should_send <- TRUE
                }
        }
        
        if (should_send) {
                discord(msg=paste0(pair," Price is ",type,": ",price,mesg),channel=channel)
                update_last_report_time(redis_key)
                cat("Alert sent for", redis_key, "at", as.character(Sys.time()), "\n")
        } else {
                cat("Rate limited: Skipping alert for", redis_key, "(last sent at", as.character(last_report_time), ")\n")
        }
}

ds_prices = function(pairs,networks,exchanges,prices_low,prices_high,native) {
        n = length(pairs)
        for (i in 1:n) { 
                pair = pairs[i]
                print(paste0("fetching: ",pair, " / network: ",networks[i],"/ exchange: ",exchanges[i]," / native: ",native[i]))
                pricechange = ds_price(pair=pairs[i],network=networks[i],exchange=exchanges[i],pricechange=TRUE,native=native[i])
                price = pricechange[1]
                print(paste0(" price : ",price))
                if (!is.null(price) && !is.na(price)) {
                        report(pair,price,"",channel="#defi-prices",pricechange)
                        if (price <= prices_low[i]) { report(pair,price,"LOW") }
                        else if (price >= prices_high[i]) { report(pair,price,"HIGH") }
                        }
                Sys.sleep(0.5)
        }
}
monitor_thread = function(tradfi_report_day=0) { 
        ds_prices(
            pairs = c("tBTC-WBTC","sUSD-USDC","alETH-WETH","alUSD-USDC"),
            networks = c(rep("optimism",4)),
            exchanges = c(rep("velodromeV2",4)),
            prices_low = c(0.995,0.91,0.94,0.98),
            prices_high = c(0.999,0.97,0.97,0.999),
            native = c(TRUE,TRUE,
                       TRUE,TRUE)
            )
        print("finished pulling prices")
        #this_day = day(today())
        #if (tradfi_report_day < this_day) {
        #       tradfi_report_day = this_day
        #       tradfi_report(symbols=c("ES=F","NQ=F","CL=F","GC=F","TSLA","AAPL","NVDA","ELF","HOOD","CELH","NIKE"),types=c(rep("Futures",4),rep("Stock",5)),names=c("S&P 500","Nasdaq","Crude Oil","Gold", "Tesla","Apple","Nvidia","Elf Beauty","Robinhood","Celsius","NIKE"))
        #}
        #return(tradfi_report_day)
}
tradfi_report = function(symbols,types,names) {
        for (i in 1:length(symbols)) { 
                candles = na.omit(tradfi_candles(symbol=symbols[i],days=1000))
                market_analysis(OHLC=candles,name=names[i],type=types[i],ticker=symbols[i])
                }
}
tradfi_candles = function(symbol="ES=F",days=500) { 
       start_date = today() - days
       getSymbols(symbol, from = start_date, to = today(), src = "yahoo")
       return(get(symbol))
}
#tradfi_candles()
discord_sep = function() { discord(msg = "-------------------",channel="#market-overview") }
market_analysis = function(OHLC,name,type,ticker) { 
        close = Cl(OHLC)
        volume = Vo(OHLC)
        weekly <- to.weekly(OHLC, OHLC = TRUE, indexAt = "endof")
        volume_w = Vo(weekly)
        close_w = Cl(weekly)
        #print(close)
        rsi = RSI(close,n=14)
        rsi_7w = RSI(close_w,n=7)
        vwma20 = VWMA(price=close,volume=volume,n=20)
        vwma20w = VWMA(price=close_w,volume=volume_w,n=20)
        distance = (tail(close,1) - tail(vwma20,1))/tail(vwma20,1)
        distance_20w = (tail(close,1) - tail(vwma20w,1))/tail(vwma20w,1)
        above = FALSE
        msg = paste0("Market: ",name," (",ticker,") / Price: $",round(last(close),2), " / Change (24h):",(head(tail(close,2),1) - tail(close))/head(tail(close,2),1)*100,"%")
        discord(msg,channel="#market-overview")
        discord_sep()
        msg = paste0("Distance to the 20d VWMA: ",round(distance*100,2),"%")
        discord(msg,channel="#market-overview")
        msg = paste0("Distance to the 20w VWMA: ",round(distance_20w*100,2),"%")
        discord(msg,channel="#market-overview")
        msg = paste("RSI(14d): ", round(last(rsi),2),"/ RSI(7w): ", round(last(rsi_7w),2))
        discord(msg,channel="#market-overview")
        discord_sep()
        monthly <- to.monthly(OHLC, OHLC = TRUE, indexAt = "endof")
        close = Cl(monthly)
}
tradfi_report_day = 0
while(1) {
        tradfi_report_day = monitor_thread(tradfi_report_day)
        Sys.sleep(60*5)
}
