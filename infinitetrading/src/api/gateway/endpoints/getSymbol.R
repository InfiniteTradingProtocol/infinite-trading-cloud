getSymbol <- function(contract, network,apiKey) {
        check = basic_check(network=network,apiKey=apiKey)
        if (check$status == "fail") return(check)
	response = tryCatch({
                conn = db_con()
                contract <- tolower(contract); network <- tolower(network)
                symbol_query <- dbGetQuery(conn, "SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?", params = list(contract, network))
                if (nrow(symbol_query) == 0) {
                        cat("No symbol found for the given contract:",contract," and network: ",network," returning NULL\n")
                        NULL
                }
                else { symbol_query$symbol }
        },
        error = function(e) {
                cat("Error obtaining the symbol for: ",contract," and network: ",network," error: ",e$message," returning NULL\n")
                 NULL
        })
        return(response)
}
getSymbolHandler <- function(contract, network) { getSymbol(contract=contract,network=network) }
pr$handle("GET", "/getSymbol", getSymbolHandler, comment = "This endpoint returns the symbol from a contract address on a given network. Returns NULL if the contract is not stored in our systems.")
