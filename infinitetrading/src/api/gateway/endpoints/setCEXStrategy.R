##########################################################################
# Set CEX Bot Strategy
#
#* @param apiKey The API key for authentication
#* @param exchange The exchange name (coinbase, binance, okx, etc)
#* @param subaccount_name The subaccount name
#* @param pair The trading pair (e.g. BTC-USD, ETH-USDT)
#* @param strategy Strategy name (e.g. crossover, ema-rsi) or 'custom'
#* @response 200 Returns success with bot_id
#* @response 400 Bad request - missing parameters
#* @response 404 Bot or strategy not found
#* @response 500 Internal server error
#* @tag CEX
#* @post /setCEXStrategy
#
##########################################################################

setCEXStrategyHandler <- function(apiKey, exchange, subaccount_name, pair, strategy) {
    tryCatch({
        # Validate API key
        if (!isValidAPIKey(apiKey)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        # Sanitize inputs
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        pair <- gsub("[^A-Z0-9-/]", "", toupper(pair))
        strategy <- gsub("[^a-zA-Z0-9_-]", "", tolower(strategy))
        
        # Validate required parameters
        if (is.null(exchange) || exchange == "") {
            return(list(status = "fail", status_code = 400, message = "exchange is required"))
        }
        if (is.null(subaccount_name) || subaccount_name == "") {
            return(list(status = "fail", status_code = 400, message = "subaccount_name is required"))
        }
        if (is.null(pair) || pair == "") {
            return(list(status = "fail", status_code = 400, message = "pair is required"))
        }
        if (is.null(strategy) || strategy == "") {
            return(list(status = "fail", status_code = 400, message = "strategy is required"))
        }
        
        # Normalize pair format
        pair <- gsub("/", "-", pair)
        
        # Build URL for Plumber API
        url <- paste0(
            pep,
            "setCEXStrategy",
            "?apiKey=", apiKey,
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", pair,
            "&strategy=", strategy
        )
        
        # Make POST request
        response <- POST(url)
        response_content <- content(response, "text", encoding = "UTF-8")
        parsed_response <- fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(
            status = "fail",
            status_code = 500,
            message = paste("Error setting CEX strategy:", e$message)
        ))
    })
}

pr$handle("POST", "/setCEXStrategy", setCEXStrategyHandler, 
          comment = "Set the strategy for a CEX bot. Use 'custom' for manual control.")
