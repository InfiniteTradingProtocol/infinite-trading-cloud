######################################################################
#* @tag Ticks
#* @get /getAllBots
#* @param apiKey:string The API key tied to the gas wallet
#* @param manager:string The manager address
#* @param signature:string EIP-191/EIP-1271 signature
#* @param network:string The blockchain network where the Safe wallet exists (e.g., base, optimism)
#* @param USD:boolean Whether to return balance in USD (default = TRUE)
#* @response 200 Returns the gas wallet balance in USD or native token
#* @response 400 Invalid request parameters
#* @response 500 Internal server error
#* @description
#* Fetches the Gas wallet balance associated with the given API key.
#* Accepts a blockchain network identifier and an optional flag to return
#* balance in USD (TRUE) or native token units (FALSE).
######################################################################

getAllBotsHandler <- function(apiKey, manager, signature, network=NULL, sigNetwork=NULL) {
  tryCatch({
    # network    = bot list filter ("all", "base", "optimism", etc.)
    # sigNetwork = chain where the Safe wallet is deployed (for EIP-1271 sig verification)
    # If sigNetwork not supplied, fall back to network (cache will make it fast after first call)
    filter_net  <- if (!is.null(network) && nchar(network) > 0) network else "all"
    sig_net     <- if (!is.null(sigNetwork) && nchar(sigNetwork) > 0) sigNetwork else filter_net
    url <- paste0(pep, "getAllBots?&manager=", manager,
                  "&network=", filter_net,
                  "&sigNetwork=", sig_net,
                  "&signature=", signature)
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
    list(error = paste("Internal server error:", e$message))
  })
}
pr$handle("GET","/getAllBots", getAllBotsHandler, comment = "Fetches all bots data associated to a manager."
)

