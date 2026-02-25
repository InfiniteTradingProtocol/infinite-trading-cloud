require(dotenv)
load_dot_env("~/infinitetrading/src/.env")
cmc_apikey = Sys.getenv("cmc_apikey")

source("~/infinitetrading/src/db.R")
# Call the function to insert the OHLCV data into the database
#insert_ohlcv_data(ohlcv_data, "ohlcv_table")
dht_price = function(platform="coingecko") {
        require(httr); require(jsonlite)
        if (platform == "coingecko") {
                require(httr); require(jsonlite)
                url <- "https://api.coingecko.com/api/v3/simple/price?ids=dhedge-dao&vs_currencies=usd"
                response <- GET(url) # Send GET request to API endpoint
                data <- fromJSON(rawToChar(response$content)) # Convert response content to JSON format
                #data = content(response,as="text")
                #print(data)
                dht_price = data$`dhedge-dao`$usd # Retrieve dhedge dao crypto price in usd
                return(dht_price)
                #print(paste("dhedge dao price in USD:", dht_price)) # Print the retrieved price
        }
        else if (platform == "coinmarketcap") {
                # API url for dHedge DAO prices
                #url <- "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest?symbol=DHT"
                # Set API key
                require(coinmarketcapr)
                setup(api_key = cmc_apikey, sandbox = FALSE)
                dht_data = get_crypto_quotes(symbol = c("DHT"))
                dht_price = dht_data$price
                return(dht_price)
        }
}
cmc_price = function(symbol) {
                require(coinmarketcapr)
                setup(api_key = cmc_apikey, sandbox = FALSE)
                coin_data = get_crypto_quotes(symbol = symbol)
                coin_price = coin_data$price
                return(coin_price)
}

