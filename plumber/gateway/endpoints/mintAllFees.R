##########################################################################
#* @hide
#* @param apiKey The API key for authentication
#* @param gasWallet The gas wallet address (the one used to generate the API KEY)
#* @param protocol The protocol to use
#* @param network The network to use (all to mint into all networks)
#* @response 200 Returns the result of the fee claiming process
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @post /mintAllFees
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

mintAllFeesHandler = function(apiKey,protocol="dhedge",network="all") {
        protocol=tolower(protocol); network = tolower(network);
        if (network =="all") { network_check = "optimism" }
	else { network_check = network }
	check = basic_check(network=network_check,protocol=protocol,apiKey=apiKey)
        response <- POST(paste0(ep,"getWallet?apiKey=",apiKey);
        response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
	if (status_code(response) == 200) {
                if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
                traderAddress = parsed_response
        }
	else { print(parsed_response); return(parsed_response) }
	print("trader address")
	print(traderAddress)
	allFunds = getallFundsByTrader(protocol,traderAddress)
	print(allFunds)
        #if (check$status == "fail") { return(check) }
        #return(list(status="success",status_code=200,message="All fees minted"))
}

pr$handle("POST","/mintAllFees",mintAllFeesHandler,comment="This endpoint is used to mint the performance and management fees from all vaults used by the gas wallet into a specified network or all networks where gas is available.")
