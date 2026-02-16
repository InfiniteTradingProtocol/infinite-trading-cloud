##########################################################################
#* @hide
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param network The network to use
#* @param pool The pool to target
#* @param assets The list of allowed assets
#* @response 200 Returns the result of setting allowed assets
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Assets
#* @get /setAllowedAssets
#
##########################################################################

setAllowedAssetsHandler =function(apiKey,protocol="dhedge",network,pool,assets) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
}

pr$handle("GET","/setAllowedAssets",setAllowedAssetsHandler,comment="This endpoint is used to change the allowed assets list inside a pool")
