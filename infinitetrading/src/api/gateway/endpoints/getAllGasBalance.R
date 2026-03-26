######################################################################
#* @tag Ticks
#* @get /getAllGasBalance
#* @param apiKey:string The API key tied to the gas wallet
#* @param network:string The blockchain network (e.g., ETH, POL)
#* @param USD:boolean Whether to return balance in USD (default = TRUE)
#* @response 200 Returns the gas wallet balance in USD or native token
#* @response 400 Invalid request parameters
#* @response 500 Internal server error
#* @description
#* Fetches the Gas wallet balance associated with the given API key.
#* Accepts a blockchain network identifier and an optional flag to return
#* balance in USD (TRUE) or native token units (FALSE).
######################################################################

getAllGasBalanceHandler <- function(apiKey, USD = TRUE,manager,signature) {
  tryCatch({
    # Construct request
    url <- paste0(pep, "getAllGasBalance?USD=", toupper(as.character(USD)),"&manager=", manager, "&network=all","&signature=",signature) 
    response <- httr::POST(url)
    response_content <- httr::content(response, "text", encoding = "UTF-8")

    # Parse response content safely
    parsed_response <- jsonlite::fromJSON(response_content)

    # Return response based on status code
    if (httr::status_code(response) == 200) {
      if (is.character(parsed_response)) {
        parsed_response <- jsonlite::fromJSON(parsed_response)
      }
      return(parsed_response)
    } else {
      warning("API responded with error status")
      return(list(error = parsed_response))
    }
  }, error = function(e) {
    # Catch parsing/network errors
    list(error = paste("Internal server error:", e$message))
  })
}
pr$handle("GET","/getAllGasBalance", getAllGasBalanceHandler, comment = "Fetches the gas wallet balance for all associated wallet for a specific manager. Set USD=TRUE to return the balance in USD; otherwise, it will return the native token value (e.g., ETH or POL)."
)

