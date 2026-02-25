###############################
#
# Gas Prices Tracker Thread
# fetch data from Etherscan
# push values to redis
#
###############################

require(httr); require(jsonlite); require(dotenv); require(redux)

load_dot_env("~/infinitetrading/src/api/.env")

r <- redux::hiredis()
chain_ids <- c(
  ethereum = 1,
  polygon  = 137,
  optimism = 10,
  arbitrum = 42161,
  base     = 8453
)

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

options(scipen=18)

gasTracker <- function(networks) {
	for (network in networks) { 
		apiKey = Sys.getenv("ETHERSCAN_APIKEY")
    		endpoint <- paste0("https://api.etherscan.io/v2/api?chainid=",get_chain_id(network),"module=gastracker&action=gasoracle&apikey=", apiKey)
    		response <- GET(endpoint)
    		if (status_code(response) == 200) {
      			response_content <- content(response, "text"); response_json <- fromJSON(response_content)
      			if (response_json$status == "1") {
				safe_gas_price <- if (!is.null(response_json$result$SafeGasPrice)) as.numeric(response_json$result$SafeGasPrice) else NA
				fast_gas_price <- if (!is.null(response_json$result$FastGasPrice)) as.numeric(response_json$result$FastGasPrice) else NA
				suggest_base_fee <- if (!is.null(response_json$result$suggestBaseFee)) as.numeric(response_json$result$suggestBaseFee) else NA
				propose_gas_price <- if (!is.null(response_json$result$ProposeGasPrice)) as.numeric(response_json$result$ProposeGasPrice) else NA
				if (all(c(!is.na(safe_gas_price),!is.na(fast_gas_price),!is.na(suggest_base_fee),!is.na(propose_gas_price)))) {
					#r$SET(paste0(network, "_UpdateTimetstamp",as.character(Sys.time())))
					r$SET(paste0(network, "_SafeGasPrice"), safe_gas_price)
					r$SET(paste0(network, "_FastGasPrice"), fast_gas_price)				
					r$SET(paste0(network, "_suggestBaseFee"), suggest_base_fee)
					r$SET(paste0(network, "_ProposeGasPrice"), propose_gas_price)
					print("Gas values pushed to redis")
					print(paste0("Network: ",network))
                                	print(paste("Safe Gas Price: ", safe_gas_price))
                                	print(paste("Fast Gas Price: ", fast_gas_price))
                                	print(paste("Suggest Base Fee: ", suggest_base_fee))
                                	print(paste("Proposed Gas Price: ", propose_gas_price))
				}
				else { print("Error: gas values not pushed to redis") } 
		}
      		else { cat("Error in response: ", response_json$message, "\n") }
    	}
    	else { cat("Error fetching data. Status code:", status_code(response), "\n") }
	}
}

networks = c("polygon","ethereum","base","arbitrum","optimism")
#curl -X 'GET' -u 89921f55e7d14d939326c2b35497bd5b:fa4a11884ba7443da77c06facf6a421d    'https://gas.api.infura.io/networks/10/suggestedGasFees'

#gasTracker(networks=networks)
#for (network in networks) { 
#	gasTracker(network)
#	print(paste0("Redis Gas Tracking for ",network)) 
#	print("safe gas")
#       print(r$GET(paste0(network,"_SafeGasPrice")))
#       print("fast gas")
#      	print(r$GET(paste0(network,"_FastGasPrice")))
#       print("suggest base fee")
#	print(r$GET(paste0(network,"_suggestBaseFee")))
#	print("propose gas price")
#	print(r$GET(paste0(network,"_ProposeGasPrice")))
#}

