##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param network The network to use
#* @param pool The pool to target
#* @response 200 Returns the current bot status
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Bot
#* @get /getBotStatus
#
##########################################################################

getBotStatusHandler =function(apiKey,protocol="dhedge",network,pool) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
        return(list(status="success",status_code=200,message="End point not available yet"))
}
pr$handle("GET","/getBotStatus",getBotStatusHandler, comment="This endpoint is used to retrieves the current bot status for a specific pool. This can be used to verify if the recorded side instructions matches your actual trading strategy side.")
