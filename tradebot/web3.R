######################@
### web3 code	     ##
### Author: Mr.Clare ##
#######################

ep = function(network) { 
  if (network == "mainnet" || network == "ethereum") {
    api_url <- "https://api.etherscan.io/api"
  } 
  else if (network == "polygon") {
    api_url <- "https://api.polygonscan.com/api"
  } 
  else if (network == "optimism") {
    api_url <- "https://api-optimistic.etherscan.io/api"
  } 
  else if (network == "arbitrum") {
    api_url <- "https://api.arbiscan.io/api"
  }
  else  { 
    stop("Invalid network parameter. Valid options are 'mainnet', 'polygon', 'optimism', or 'arbitrum'.")
  }
  return(api_url) 
}
get_tx_status <- function(tx_hash, network) {
  require(httr)
  # Set the Etherscan API endpoint URL based on the network parameter
  api_url = ep(network)
  
  # Set the Etherscan API endpoint parameters
  api_params <- list(
    module = "transaction",
    action = "gettxreceiptstatus",
    txhash = tx_hash
  )
  
  # Make the API call to get the transaction status
  api_response <- httr::GET(api_url, query = api_params)
  api_content <- httr::content(api_response)
  #print(api_content)
  # Check if the API call was successful
  if (api_response$status_code != 200) {
    stop("Error: API call failed with status code ", api_response$status_code)
  }
  
  # Check if the transaction was found
  if (api_content$status != "1") {
    stop("Error: Transaction not found or invalid transaction hash.")
  }
  
  # Return the transaction status
  if (network == "mainnet") {
    if (api_content$result["isError"] == "1") {
      return("Error")
    } else if (as.numeric(api_content$result["status"]) == 1) {
      return("Success")
    } else {
    return("Pending")
    }
  }
  else if (network == "polygon") { 
    if (api_content$result$status == "0") {
      return("Error")
    } else if (as.numeric(api_content$result["status"]) == 1) {
      return("Success")
    } else {
      return("Pending")
    }
  }
}
wallet_balance = function(address,network="polygon") {
  require(httr)
  require(jsonlite)
  url <- paste0(ep(network),
                "?module=account",
                "&action=balance",
                "&address=", address,
                "&tag=latest")
  response <- GET(url)
  # Parse the JSON response
  content <- fromJSON(content(response, "text"), simplifyVector = TRUE)
  # Extract the gas balance
  gas_balance <- as.numeric(content$result) / 10^18 
  # Print the gas balance
  return(gas_balance)
}
