#####################################################################
#
#* @response 200 Associate a new gas wallet to the manager.
#* @response 500 Internal server error
#* @tag Private
#* @get /associateGasWallet
#
######################################################################

associateGasWalletHandler <- function(apiKey,manager,label="main",signature,network=NULL) {
    # Build the request URL to the main API
    label = substr(label, 1, min(42, nchar(label)))
    url <- paste0(pep, "associateGasWallet?",
                  "apiKey=", apiKey,
                  "&manager=", manager,"&label=",label,"&signature=",signature)
    if (!is.null(network) && nchar(network) > 0) url <- paste0(url, "&network=", network)

    # Send the request to the main API
    print("sending request to ")
    print(url)
    response <- POST(url)

    # Read and parse the response
    response_content <- content(response, "text")
    parsed_response <- fromJSON(response_content)

    if (is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
    print(parsed_response)
    return(parsed_response)
}

pr$handle("POST","/associateGasWallet",associateGasWalletHandler,comment="This endpoint associates a gas wallet with a manager. (internal use for front-end)")

