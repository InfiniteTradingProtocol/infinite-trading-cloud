##########################################################################
# Get All CEX Subaccounts
#* @param manager The manager wallet address
#* @param signature Wallet signature for authentication
#* @response 200 Returns all subaccounts for manager
#* @tag CEX
#* @get /getAllCEXSubaccounts
##########################################################################

getAllCEXSubaccountsHandler <- function(manager, signature = NULL) {
    tryCatch({
        manager <- tolower(manager)
        
        url <- paste0(
            pep, "getAllCEXSubaccounts",
            "?manager=", URLencode(manager, reserved = TRUE),
            "&signature=", URLencode(signature, reserved = TRUE)
        )
        
        response <- httr::GET(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("GET", "/getAllCEXSubaccounts", getAllCEXSubaccountsHandler, 
          comment = "Get all CEX subaccounts for a manager wallet")
