#######################################################
#
#* @param network:str The network to use
#* @param network enum polygon,optimism,arbitrum
#* @param protocol The protocol to use (dhedge)
#* @param pool The pool to target
#* @param apiKey The API key for authentication
#* @response 200 Returns the result of the unlinking process
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @delete /unlinkGasWallet
#
#######################################################


unlinkGasWalletHandler = function(network,protocol="dhedge",pool,apiKey) {
        network = tolower(network); protocol=tolower(protocol); pool = tolower(pool); check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
	if (check$status == "fail")  {
		print(check)
		return(check)
	}
        response <- POST(paste0(pep,"unlinkGasWallet?network=",network,"&protocol=",protocol,"&pool=",pool,"&apiKey=",apiKey))
        response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
        print(parsed_response)
        return(parsed_response)
}

pr$handle("DELETE","/unlinkGasWallet",unlinkGasWalletHandler,comment="This endpoint deassociates a gas wallet from a pool on the specified network and protocol.")
