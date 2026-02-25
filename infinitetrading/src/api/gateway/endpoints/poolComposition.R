poolCompositionHandler <- function(pool, network, protocol,apiKey) {
       check = basic_check(pool=pool,network=network,protocol=protocol,apiKey=apiKey)

       if (check$status == "fail") { return(check) }
       #here i need to invoke the other endpoint,and verify apiKeys.
       pool_comp(pool,network,protocol)
}
pr$handle("GET", "/poolComposition", poolCompositionHandler, serializer = serializer_json(), comment = "This endpoint retrieves the composition of a specified pool on a given network and protocol")
