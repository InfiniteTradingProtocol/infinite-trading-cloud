##########################################################################
# Get CEX Side
#* @param gas_wallet_api_key The gas wallet API key for authentication
#* @param subaccount_name The subaccount name
#* @param pair The trading pair (e.g. BTC-USD) - optional, if not provided returns all bots
#* @response 200 Bot details retrieved successfully
#* @response 404 Subaccount or bot not found
#* @response 500 Internal server error
#* @tag CEX
#* @get /getCEXSide
##########################################################################

getCEXSideHandler <- function(gas_wallet_api_key, subaccount_name, pair = NULL) {
    tryCatch({
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        
        url <- paste0(
            pep, "getCEXSide",
            "?gas_wallet_api_key=", URLencode(gas_wallet_api_key, reserved = TRUE),
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE)
        )
        
        if (!is.null(pair) && pair != "") {
            pair <- gsub("[^A-Z0-9/-]", "", toupper(pair))
            url <- paste0(url, "&pair=", pair)
        }
        
        response <- httr::GET(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("GET", "/getCEXSide", getCEXSideHandler, 
          comment = "Get trading side and parameters for CEX bot(s)")
