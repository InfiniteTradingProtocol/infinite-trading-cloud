##########################################################################
#
#* @param network The network to use
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param apiKey The API key for authentication
#* @response 200 Returns the result of the unlinking process
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Wallet
#* @get /unlinkGasWallet
#
##########################################################################

getCurrentAllocationsHandler = function(apiKey,protocol="dhedge",pool,network) {
    #params = list(apiKey=apiKey,protocol=protocol,pool=pool,network=network)
    protocol = tolower(protocol); pool=tolower(pool); network = tolower(network)
    check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
    if (check$status == "fail") { return(check) }
    url <- paste0(pep,"getAllocations?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network)
    #url = paste0(pep,"getAllocations")
    # Perform the POST request
    print(url)
    response <- POST(url)
    # Parse the JSON response
    response_content <- content(response,as = "text")
    parsed_response <- fromJSON(response_content)
    print("checking")
    print(parsed_response)
    masked_api = mask_api(apiKey)
    #Check the status code of the response
    if (status_code(response) == 200) {
            discord(msg=paste0("getAllocations endpoint invoked by apiKey: ", masked_api, " / pool: ",pool," / protocol: ", protocol,"/ response: ",response_content),channel="#api-logs",db=FALSE)
    }
    else {
            discord(msg=paste0("Failed getAllocations endpoint invoked by apiKey: ", masked_api , " / pool: ",pool," / protocol: ", protocol, " / response: ",response_content),channel="#api-logs",db=FALSE)
    }
    return(parsed_response)
}

pr$handle("GET","/getCurrentAllocations",getCurrentAllocationsHandler,comment = "This endpoint returns the current allocation strategy for a specific pool, protocol and network")
