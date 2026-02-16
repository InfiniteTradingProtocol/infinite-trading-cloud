require(httr); require(jsonlite); require(dotenv)
tryCatch({
  if (file.exists(".env")) load_dot_env(".env")
  else if (file.exists("plumber/.env")) load_dot_env("plumber/.env")
  else if (exists("wd") && file.exists(paste0(wd, "plumber/.env"))) load_dot_env(paste0(wd, "plumber/.env"))
}, error=function(e) { print("Note: No .env file loaded (optional)") })

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
print(get_chain_id("polygon"))
#ethetscan max batch
max_batch_size = as.numeric(Sys.getenv("max_batch_size"))

#rate limit from etherscan is 5 tx/s
#we can fetch 100 gas wallet per second.
sleep_interval = as.numeric(Sys.getenv("sleep_interval"))
getGasBalances <- function(addresses, network, structured = FALSE) {
  max_batch_size <- 20
  sleep_interval <- 1

  get_single_network_balances <- function(addresses, net) {
    apiKey <- Sys.getenv("ETHERSCAN_APIKEY")
    address_batches <- split(addresses, ceiling(seq_along(addresses) / max_batch_size))
    balances <- c()
    structured_list <- list()
    initial <- TRUE

    for (batch in address_batches) {
      address_list <- paste(batch, collapse = ",")
      endpoint <- paste0("https://api.etherscan.io/v2/api?chainid=",get_chain_id(net),"&module=account&action=balancemulti&address=", address_list, "&tag=latest&apikey=", apiKey)
      if (!initial) Sys.sleep(sleep_interval)
      initial <- FALSE

      response <- GET(endpoint)
      if (status_code(response) == 200) {
        response_json <- fromJSON(content(response, "text"))
        if (response_json$status == "1") {
          for (i in seq_along(response_json$result$account)) {
            bal <- as.numeric(response_json$result$balance[i]) / 1e18
            balances <- c(balances, bal)
            structured_list[[length(structured_list) + 1]] <- list(
              network = net,
              wallet = response_json$result$account[i],
              balance = bal
            )
          }
        } else {
          cat("Error in response for", net, ":", response_json$message, "\n")
        }
      } else {
        cat("Error fetching data from", net, "- Status code:", status_code(response), "\n")
      }
    }

    if (structured) return(structured_list)
    else return(as.numeric(balances))
  }

  if (network == "all") {
    if (!structured) stop("Use structured = TRUE when querying multiple networks.")
    results <- list()
    for (net in networks) {
      results <- append(results, get_single_network_balances(addresses, net))
    }
    return(results)
  } else {
    return(get_single_network_balances(addresses, network))
  }
}

#Test script

#getGasBalances("0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5",network="all",structured=TRUE)
