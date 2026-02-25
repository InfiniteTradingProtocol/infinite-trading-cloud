######################################################################
#
#* @response 200 Returns the newly created gas wallet information including address, private key, and API key
#* @response 500 Internal server error
#* @tag Wallet
#* @get /createGasWallet
#
######################################################################

createGasWalletHandler <- function() {
    response <- POST(paste0(pep,"createWallet")); response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        if(is.list(parsed_response) && length(parsed_response) == 1) parsed_response <- fromJSON(parsed_response[[1]])
        address <- unlist(parsed_response$address)[1]; private_key <- unlist(parsed_response$privateKey)[1]; api_key <- unlist(parsed_response$apiKey)[1]
        cat("Address: ", address, "\n"); cat("Private Key: ", private_key, "\n"); cat("API Key: ", api_key, "\n"); cat("isValidAPIKey: ", isValidAPIKey(api_key), "\n")
        return(list(status="success",status_code=200,address=address,private_key=private_key,apiKey=api_key))
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/createGasWallet",createGasWalletHandler,comment="This endpoint creates a new Ethereum gas wallet and returns the address, private keys, and API keys.")
