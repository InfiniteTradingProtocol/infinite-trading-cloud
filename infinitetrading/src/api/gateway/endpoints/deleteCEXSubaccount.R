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
        
        # Build URL for Plumber API
        url <- paste0(
            pep,
            "deleteCEXSubaccount",
            "?apiKey=", apiKey,
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE)
        )
        
        # Make DELETE request
        response <- httr::DELETE(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Server error:", e$message)))
    })
}

pr$handle("DELETE", "/deleteCEXSubaccount", deleteCEXSubaccountHandler, 
          comment = "Delete a CEX subaccount. This will CASCADE delete all associated bots and trades.")
