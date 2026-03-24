##########################################################################
# Delete CEX Subaccount
#
#* @param apiKey The API key for authentication
#* @param exchange The exchange name
#* @param subaccount_name The subaccount name to delete
#* @response 200 Subaccount deleted successfully
#* @response 400 Bad request - missing parameters
#* @response 404 Subaccount not found
#* @response 500 Internal server error
#* @tag CEX
#* @delete /deleteCEXSubaccount
#
##########################################################################

deleteCEXSubaccountHandler <- function(apiKey, exchange, subaccount_name) {
    tryCatch({
        # Validate API key
        if (!isValidAPIKey(apiKey)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        # Sanitize inputs
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        
        # Validate required parameters
        if (is.null(exchange) || exchange == "") {
            return(list(status = "fail", status_code = 400, message = "exchange is required"))
        }
        if (is.null(subaccount_name) || subaccount_name == "") {
            return(list(status = "fail", status_code = 400, message = "subaccount_name is required"))
        }
        
        # Forward to Plumber API (pep) - this will CASCADE delete all bots and trades
        payload <- list(
            apiKey = apiKey,
            exchange = exchange,
            subaccount_name = subaccount_name
        )
        
        response <- httr::DELETE(
            paste0(pep, "/deleteCEXSubaccount"),
            body = payload,
            encode = "json"
        )
        
        result <- httr::content(response, as = "parsed")
        return(result)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Server error:", e$message)))
    })
}
