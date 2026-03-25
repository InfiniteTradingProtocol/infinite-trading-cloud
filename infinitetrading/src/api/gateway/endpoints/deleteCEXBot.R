##########################################################################
# Delete CEX Bot
#* @param gas_wallet_api_key The gas wallet API key for authentication
#* @param subaccount_name The subaccount name
#* @param pair The trading pair
#* @response 200 Bot deleted successfully
#* @tag CEX
#* @delete /deleteCEXBot
##########################################################################

deleteCEXBotHandler <- function(gas_wallet_api_key, subaccount_name, pair) {
    tryCatch({
        if (!isValidAPIKey(gas_wallet_api_key)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        pair <- gsub("[^A-Z0-9/-]", "", toupper(pair))
        
        url <- paste0(
            pep, "deleteCEXBot",
            "?gas_wallet_api_key=", URLencode(gas_wallet_api_key, reserved = TRUE),
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", pair
        )
        
        response <- httr::DELETE(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("DELETE", "/deleteCEXBot", deleteCEXBotHandler, 
          comment = "Delete a CEX bot configuration")
