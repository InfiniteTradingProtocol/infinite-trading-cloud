##########################################################################
# Set CEX Strategy
#* @param gas_wallet_api_key The gas wallet API key for authentication
#* @param subaccount_name The subaccount name
#* @param pair The trading pair
#* @param strategy The strategy name
#* @response 200 Strategy updated successfully
#* @tag CEX
#* @post /setCEXStrategy
##########################################################################

setCEXStrategyHandler <- function(gas_wallet_api_key, subaccount_name, pair, strategy) {
    tryCatch({
        url <- paste0(
            pep, "setCEXStrategy",
            "?gas_wallet_api_key=", URLencode(gas_wallet_api_key, reserved = TRUE),
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", gsub("[^A-Z0-9/-]", "", toupper(pair)),
            "&strategy=", tolower(strategy)
        )
        
        response <- httr::POST(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("POST", "/setCEXStrategy", setCEXStrategyHandler, 
          comment = "Set automated trading strategy for a CEX bot")
