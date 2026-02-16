getContract <- function(symbol, network,apiKey) {
        check = basic_check(network=network,apiKey=apiKey)
        if (check$status == "fail") return(check)
        response <- tryCatch({
                conn = db_con()
                symbol <- tolower(symbol); network <- tolower(network)
                contract_query <- dbGetQuery(conn, "SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?", params = list(symbol, network))
                if (nrow(contract_query) == 0) {
                        cat("Warning: No contract found for the given symbol: ",symbol," and network: ",network," returning NULL\n")
                        NULL
                }
                else { contract_query$contract }
                },
                error = function(e) {
                        cat("Error obtaining the contract for: ",symbol," and network: ",network," error: ",e$message," returning NULL\n")
                        NULL
                })
        return(response)
}

getContractHandler <- function(symbol, network) { getContract(symbol=symbol,network=network) }
pr$handle("GET", "/getContract", getContractHandler, comment = "This endpoint returns the contract address for a specified coin on a given network. Returns NULL if the symbol is not stored in our systems.")
