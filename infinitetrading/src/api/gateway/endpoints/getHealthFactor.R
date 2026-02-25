##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param platform The platform to use (default is AAVE)
#* @response 200 Returns the result of the health factor of a position
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag getHealthFactor
#* @get /getHealthFactor
#
##########################################################################

getHealthFactorHandler = function(apiKey,protocol="dhedge",pool,network,platform="AAVE") {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
	url <- paste0(pep,"getHealthFactor?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&platform=",platform)
	# Perform the POST request
	response <- POST(url); content_response = content(response,"text"); parsed_response <- fromJSON(content_response)
        return(parsed_response)
}
pr$handle("GET","/getHealthFactor",getHealthFactorHandler,comment = "Allows managers to retrieve the health factor of their position on the specific pool.")
  
