##################################################################
#
#* @param privateKey The private key to generate a new API key
#* @response 200 Returns the newly generated API key
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Wallet
#* @get /getNewApiKey
#
##################################################################

getNewApiKeyHandler = function(privateKey) {
        if (!isValidEthPrivateKey(privateKey)) return(list(status="fail",status_code=400,message="The provided private key is not valid to generate an API Key."))
        response <- POST(paste0(pep,"getApiKey?&privateKey=",privateKey))
        response_content <- content(response, "text")
        parsed_response <- fromJSON(response_content)
        if (status_code(response) == 200) {
                if (is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
                if (is.list(parsed_response) && length(parsed_response) == 1) parsed_response <- fromJSON(parsed_response[[1]])
                api_key <- unlist(parsed_response$apiKey)[1]
                cat("API Key: ", api_key, "\n"); cat("isValidAPIKey: ", isValidAPIKey(api_key), "\n")
                return(list(status="success",status_code=200,apiKey=api_key,message="The API for the provided private key has been succesfully generated."))
        }
        print(parsed_response)
        return(parsed_response)
}

pr$handle("GET","/getNewApiKey", getNewApiKeyHandler,comment="This endpoint receives a private key and returns an API Key. This can be used to import and link existing gas wallets. Warning: a new API key is generated every time this endpoint is invoked, and cant be used to obtain existing API keys for linked gas wallets.")
