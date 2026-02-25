##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @response 200 Returns the whole AAVE account data por the pool
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag getPoolAaveData
#* @get /getPoolAaveData
#
##########################################################################

getPoolAaveDataHandler = function(apiKey,protocol="dhedge",pool,network) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); 
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
	url <- paste0(pep,"getPoolAaveData?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network)
	# Perform the POST request
	response <- POST(url); content_response = content(response,"text"); parsed_response <- fromJSON(content_response)
        return(parsed_response)
}
pr$handle("GET","/getPoolAaveData",getPoolAaveDataHandler,comment = "Allows managers to retrieve the account data on AAVE of their position on the specific pool.")
  
