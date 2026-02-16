######################################################################
#* @tag Ticks
#* @get /getGasBalance
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

getGasBalanceHandler <- function(apiKey, network, USD = TRUE,manager=FALSE) {
  tryCatch({
    if (missing(apiKey) || missing(network)) return(list(error = "Missing required parameters: apiKey or network"))
    url <- paste0(pep, "getGasBalance?USD=", toupper(as.character(USD)),"&apiKey=", apiKey, "&network=", network) 
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
pr$handle("GET","/getGasBalance", getGasBalanceHandler, comment = "Fetches the gas wallet balance for a specified API key and network. Set USD=TRUE to return the balance in USD; otherwise, it will return the native token value (e.g., ETH or POL)."
)

