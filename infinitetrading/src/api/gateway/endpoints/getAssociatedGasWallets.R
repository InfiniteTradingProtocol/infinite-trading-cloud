######################################################################
#
#* @response 200 Returns the list of associated gas wallet to a manager
#* @response 500 Internal server error
#* @tag Private
#* @get /getAssociatedGasWallets
#
######################################################################

getAssociatedGasWalletsHandler <- function(apiKey=NULL, manager=NULL, signature=NULL, network=NULL) {
    # Build the request URL to the main API
    url <- paste0(pep, "getAssociatedGasWallets?",
                  "apiKey=", apiKey,
                  "&manager=", manager,"&signature=",signature)
    if (!is.null(network) && nchar(network) > 0) url <- paste0(url, "&network=", network)

    # Send the request to the main API
    response <- POST(url)

    # Read and parse the response
    response_content <- content(response, "text")
    parsed_response <- fromJSON(response_content)

    # Handle double encoded JSON
    if (status_code(response) == 200) {
        if (is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        return(parsed_response)
    } else {
        print(parsed_response)
        return(parsed_response)
    }
}

pr$handle("GET","/getAssociatedGasWallets",getAssociatedGasWalletsHandler,comment="This endpoint returns a list of all gas wallets associated to the specific manager wallet. (internal use for front-end)")

