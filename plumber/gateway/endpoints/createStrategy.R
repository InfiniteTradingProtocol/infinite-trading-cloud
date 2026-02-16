createStrategyHandler =function(apiKey,protocol,network,pool,strategy) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
}

pr$handle("GET","/createStrategy",createStrategyHandler, comment="This endpoint is used to deploy pre-made strategies by Infinite Trading into the specified pools.")
