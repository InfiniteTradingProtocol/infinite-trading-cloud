##########################################################################
#* @hide
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param network The network to use
#* @param pool The pool to target
#* @response 200 Returns the result of the fee claiming process
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @post /mintManagerFees
#
##########################################################################

mintFeesHandler =function(apiKey,protocol="dhedge",network,pool) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
	response <- POST(paste0(pep,"mintFees?&pool=",pool,"&apiKey=",apiKey,"&network=",network,"&protocol=",protocol));
    	response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    	if (status_code(response) == 200) {
        	if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        	parsed_response
    	}
    	else { print(parsed_response); return(parsed_response) }
}

pr$handle("POST","/mintManagerFee",mintFeesHandler,comment="This endpoint is used to mint performance and management fees into a specified pool.")

