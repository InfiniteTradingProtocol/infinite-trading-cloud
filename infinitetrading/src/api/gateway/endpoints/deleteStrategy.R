deleteStrategyHandler =function(apiKey,protocol,network,pool) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
}
pr$handle("GET","/deleteStrategy",deleteStrategyHandler,comment="This endpoint is used to turn off any strategy associated to the specified pool")
