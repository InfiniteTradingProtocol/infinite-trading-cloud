##########################################################################
# Set CEX Side
#* @param gas_wallet_api_key The gas wallet API key for authentication
#* @param subaccount_name The subaccount name
#* @param pair The trading pair (e.g. BTC-USD)
#* @param side The side to set (long, neutral)
#* @param max_usd Maximum USD to trade
#* @param share Share/allocation percentage
#* @param strategy Optional strategy name
#* @response 200 Bot updated successfully
#* @response 400 Bad request
#* @response 404 Subaccount not found
#* @response 500 Internal server error
#* @tag CEX
#* @post /setCEXSide
##########################################################################

setCEXSideHandler <- function(gas_wallet_api_key, subaccount_name, pair, side, max_usd, share, strategy = NULL) {
    tryCatch({
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        pair <- gsub("[^A-Z0-9/-]", "", toupper(pair))
        side <- tolower(side)
        
        url <- paste0(
            pep, "setCEXSide",
            "?gas_wallet_api_key=", URLencode(gas_wallet_api_key, reserved = TRUE),
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", pair,
            "&side=", side,
            "&max_usd=", max_usd,
            "&share=", share
        )
        
        if (!is.null(strategy) && strategy != "") {
            url <- paste0(url, "&strategy=", strategy)
        }
        
        response <- httr::POST(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("POST", "/setCEXSide", setCEXSideHandler, 
          comment = "Set trading side and parameters for a CEX bot")
