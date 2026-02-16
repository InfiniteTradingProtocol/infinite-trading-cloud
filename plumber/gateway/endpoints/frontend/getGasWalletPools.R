######################################################################
#
#* @response 200 Returns the linked pools associated with the provided gas wallet
#* @response 500 Internal server error
#* @tag Private
#* @get /getGasWalletPools
#
######################################################################

getGasWalletPoolsHandler <- function(apiKey, protocol="dhedge", network="all", wallet) {
    # Build the request URL to the main API
    url <- paste0(pep, "getGasWalletPools?",
                  "apiKey=", apiKey,
                  "&protocol=", protocol,
                  "&network=", network,
                  "&wallet=", wallet)

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

pr$handle("GET","/getGasWalletPools",getGasWalletPoolsHandler,
          comment="This endpoint returns a list of all pools linked to the specified gas wallet. (internal use for front-end)")

