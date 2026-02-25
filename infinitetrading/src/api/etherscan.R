require(httr); require(jsonlite); require(dotenv)
load_dot_env("~/infinitetrading/src/api/.env")

chain_ids <- c(
  ethereum = 1,
  polygon  = 137,
  optimism = 10,
  arbitrum = 42161,
  base     = 8453
)

networks = c("ethereum","polygon","base","arbitrum","optimism")

get_chain_id <- function(network) {
  if (is.numeric(network)) {
    # already an ID
    return(as.integer(network))
  }
  key <- tolower(as.character(network))
  id <- chain_ids[[key]]
  if (is.null(id)) stop("Unknown network: ", network)
  return(id)
}
ETHERSCAN_URL <- Sys.getenv("ETHERSCAN_URL")

ETHERSCAN_APIKEY <- Sys.getenv("ETHERSCAN_APIKEY")

etherscan = function(network,params,apiKey=ETHERSCAN_APIKEY) { 
	endpoint <- paste0(ETHERSCAN_URL,"chainid=",get_chain_id(net),params,"&apikey=", apiKey)
	response <- GET(endpoint)
	if (status_code(response) == 200) { return(fromJSON(content(response, "text"))) } 
	else { cat("Error in response for", net, ":", response_json$message, "\n") }
}
