#####################################################################
#* @response 200 deassociate a new gas wallet to the manager.
#* @response 500 Internal server error
#* @tag Private
#* @delete /deassociateGasWallet
#
######################################################################

deassociateGasWalletHandler <- function(apiKey,wallet, manager,signature) {
    # Build the request URL to the main API
    url <- paste0(pep, "deassociateGasWallet?apiKey=",apiKey,"&manager=", manager,"&wallet=",wallet,"&signature=",signature)

    # Send the request to the main API
    response <- POST(url)

    # Read and parse the response
    response_content <- content(response, "text")
    parsed_response <- fromJSON(response_content)

    if (is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
    print(parsed_response)
    return(parsed_response)
}

pr$handle("DELETE","/deassociateGasWallet",deassociateGasWalletHandler,comment="This endpoint deassociates a gas wallet with a manager. (internal use for front-end)")

