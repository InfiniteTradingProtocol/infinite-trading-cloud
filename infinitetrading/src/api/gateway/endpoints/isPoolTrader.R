##########################################################################
#* @hide
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param network The network to use
#* @param pool The pool to target
#* @response 200 Returns the verification result
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Trader
#* @get /isPoolTrader
#
##########################################################################

isPoolTraderHandler =function(apiKey,protocol="dhedge",network,pool) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
}

pr$handle("GET","/isPoolTrader",isPoolTraderHandler,comment="This endpoint is used to verify if the gas wallet associated with the apiKey is a trader into the specified pool. Returns TRUE/FALSE")
