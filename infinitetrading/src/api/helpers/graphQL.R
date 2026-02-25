library(httr)
library(jsonlite)
source("~/infinitetrading/src/api/db.R")
fetchGraphQL <- function(operationsDoc, operationName, variables) {
  body <- list(query = operationsDoc,variables = variables,operationName = operationName)
  response <- POST(url = "https://api-v2.dhedge.org/graphql",body = body,encode = "json")
  content(response, as = "parsed", type = "application/json")
}

getPoolTrader <- function(protocol,pool) {
	if (protocol == "dhedge") { 
  		operationsDoc <- sprintf('query allFundsByAddresses { allFundsByAddresses(addresses: "%s") { traderAddress } }', pool)
  		result <- fetchGraphQL(operationsDoc, "allFundsByAddresses", list()) 
  		if ("errors" %in% names(result)) { cat("Error:", result$errors[[1]]$message, "\n"); return(NULL)  } 
		else if ("data" %in% names(result) && length(result$data$allFundsByAddresses) > 0) { return(result$data$allFundsByAddresses[[1]]$traderAddress) } 
		else { cat("No data found or invalid address provided.\n"); return(NULL) }
  	}
}

getallFundsByTrader <- function(protocol,traderAddress) {
        if (protocol == "dhedge") {
                operationsDoc <- sprintf('query allFundsByTrader { allFundsByTrader(traderAddress: "%s") { address blockchainCode } }', traderAddress)
                result <- fetchGraphQL(operationsDoc, "allFundsByTrader", list())
		n_pools = length(result$data$allFundsByTrader)
		pools = c(); networks = c();
		if ("errors" %in% names(result)) { cat("Error:", result$errors[[1]]$message, "\n"); return(NULL)  }
		else if ("data" %in% names(result) && n_pools > 0) { 
			for (i in 1:n_pools) { 
				pools = c(pools,result$data$allFundsByTrader[[i]]$address)
				networks = c(networks,result$data$allFundsByTrader[[i]]$blockchainCode)
			}
			return(cbind(pools,networks))
		}
                else { cat("No data found or invalid address provided.\n"); return(NULL) }
        }
}
#getallFundsByTrader(protocol="dhedge",traderAddress="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5")
# Function to fetch the token price history for a pool
getPoolTokenPrice <- function(protocol, pool = "0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320", period = "1y") {
  if (protocol == "dhedge") {
    operationsDoc <- sprintf('
      query tokenPriceHistory {
        tokenPriceHistory(address: "%s", period: "%s") {
          history {
            timestamp
            performance
            adjustedPerformance
            adjustedTokenPrice
            tokenPrice
          }
        }
      }
    ', pool, period)
    
    result <- fetchGraphQL(operationsDoc, "tokenPriceHistory", list())
    
    if ("errors" %in% names(result)) {
      cat("Error:", result$errors[[1]]$message, "\n")
      return(NULL)
    } else if ("data" %in% names(result) && length(result$data$tokenPriceHistory$history) > 0) {
         history = result$data$tokenPriceHistory$history
    	 n = length(history)
	 timestamps = c(); adjustedTokenPrices = c()
	 for (i in 1:n) {
		hist = history[[i]]
	 	timestamps = c(timestamps,as.numeric(hist$timestamp))
	 	adjustedTokenPrices = c(adjustedTokenPrices,hist$adjustedTokenPrice)
	 }
	     # If timestamps are in milliseconds, divide by 1000
    	if (max(timestamps) > 1e10) {
        	timestamps = timestamps / 1000
    	}
    	 dates = as.POSIXct(timestamps, origin = "1970-01-01", tz = "UTC")
	 return(cbind(dates,adjustedTokenPrices))
	 #return(result$data$tokenPriceHistory$history)
    } else {
      cat("No data found or invalid parameters provided.\n")
      return(NULL)
    }
  }
}

# Example usage
# address <- "0xd8e1ed48f2ff726642e1caeae2dafc8a2f9aef01"  # Example address
# trader <- getPoolTrader(protocol="dhedge", pool=address)
# print(trader)
