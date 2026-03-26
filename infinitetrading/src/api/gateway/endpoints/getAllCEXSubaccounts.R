######################################################################
#
#* @response 200 Returns the list of CEX subaccounts for a manager
#* @response 500 Internal server error
#* @tag Private
#* @get /getAllCEXSubaccounts
#
######################################################################

getAllCEXSubaccountsHandler <- function(manager, signature = NULL) {
    tryCatch({
        # Build the request URL to the main API
        url <- paste0(pep, "getAllCEXSubaccounts?",
                      "manager=", URLencode(manager, reserved = TRUE),
                      "&signature=", URLencode(signature, reserved = TRUE))

        # Send the request to the main API
        response <- GET(url)

        # Read and parse the response
        response_content <- content(response, "text")
        parsed_response <- fromJSON(response_content)

        # Handle double encoded JSON
        if (status_code(response) == 200) {
            if (is.character(parsed_response)) {
                parsed_response <- fromJSON(parsed_response)
            }
            return(parsed_response)
        } else {
            print(parsed_response)
            return(parsed_response)
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, 
                   message = paste("Error:", e$message)))
    })
}

pr$handle("GET", "/getAllCEXSubaccounts", getAllCEXSubaccountsHandler,
          comment = "This endpoint returns all CEX subaccounts for a specific manager wallet. (internal use for front-end)")
