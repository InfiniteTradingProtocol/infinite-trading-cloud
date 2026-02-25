library(future)
library(promises)
library(httr)
library(jsonlite)

# Function to send Ethereum transaction
send_transaction <- function(api_endpoint, transaction_data) {
  response <- POST(api_endpoint, body = toJSON(transaction_data), encode = "json")
  content(response, "parsed")
}

# Function to get transaction receipt
get_receipt <- function(api_endpoint, tx_hash) {
  Sys.sleep(5)  # Simulate delay for transaction confirmation
  response <- GET(paste0(api_endpoint, "/", tx_hash))
  content(response, "parsed")
}

# Async function to handle the transaction and receipt retrieval
process_transaction_async <- function(api_endpoint, transaction_data) {
  future({
    tx_response <- send_transaction(api_endpoint, transaction_data)
    tx_hash <- tx_response$txHash  # Assume the response contains the transaction hash
    receipt <- get_receipt(api_endpoint, tx_hash)
    receipt
  }) %...>% {
    # Handle the receipt here
    print("Transaction Receipt:")
    print(.)
  } %...!% {
    # Handle any errors here
    print("Error occurred:")
    print(.)
  }
}

# Example usage
api_endpoint <- "https://api.your-ethereum-node.com/transactions"
transaction_data <- list(
  from = "0xYourAddress",
  to = "0xRecipientAddress",
  value = "0xAmountInHex"
)

# Process the transaction asynchronously
process_transaction_async(api_endpoint, transaction_data)

# Continue with other tasks here
print("Continuing with other tasks...")

