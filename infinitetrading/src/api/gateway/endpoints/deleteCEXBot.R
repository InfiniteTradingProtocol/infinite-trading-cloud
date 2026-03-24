##########################################################################
# Delete CEX Bot
#
#* @param apiKey The API key for authentication
#* @param exchange The exchange name (coinbase, binance, okx, etc)
#* @param subaccount_name The subaccount name
#* @param pair The trading pair (e.g. BTC-USD, ETH-USDT)
#* @response 200 Bot deleted successfully
#* @response 400 Bad request
#* @response 404 Bot not found
#* @response 500 Internal server error
#* @tag CEX
#* @post /deleteCEXBot
#
##########################################################################

deleteCEXBotHandler <- function(apiKey, exchange, subaccount_name, pair) {
    tryCatch({
        # Validate API key
        if (!isValidAPIKey(apiKey)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        # Sanitize inputs
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        pair <- gsub("[^A-Z0-9-/]", "", toupper(pair))
        
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
        
        # Normalize pair format
        pair <- gsub("/", "-", pair)
        
        # Build URL for Plumber API
        url <- paste0(
            pep,
            "deleteCEXBot",
            "?apiKey=", apiKey,
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", pair
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
            message = paste("Error deleting CEX bot:", e$message)
        ))
    })
}

pr$handle("POST", "/deleteCEXBot", deleteCEXBotHandler, 
          comment = "Delete a CEX bot configuration. This permanently removes the bot.")
