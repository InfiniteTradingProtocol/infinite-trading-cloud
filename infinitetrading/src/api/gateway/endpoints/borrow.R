##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param asset The asset to borrow (name or contract: Example: USDC or USDC contract address on that network)
#* @param share The share of the maximum available borrow limit to use (default 100 to borrow max available)
#* @param amount This is the amount of the specified asset to borrow (optional, if you use share this will be ignored)
#* @param platform The platform to use (default is AAVE)
#* @response 200 Returns the result of the borrow transaction.
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag borrow
#* @post /borrow
#
##########################################################################

borrowHandler <- function(apiKey, protocol = "dhedge", pool, network, asset, amount, platform = "AAVE") {
  protocol <- tolower(protocol)
  pool <- tolower(pool)
  network <- tolower(network)
  platform <- tolower(platform)

  check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
  if (check$status == "fail") return(check)

  url <- paste0(pep, "borrow?apiKey=", apiKey, "&protocol=", protocol, "&pool=", pool,
                "&network=", network, "&asset=", asset, "&platform=", platform)

  res <- list(status = "success")

  #I need to know the max amount available to borrow to be able to use share

  #if (!is.null(share)) {
  #  if (!is.na(share) && is.numeric(share)) {
  #    if (share >= 1 && share <= 100) {
  #      share <- round(share)
  #      url <- paste0(url, "&share=", share)
  #    } else {
  #      res <- list(status = "fail", status_code = 1007, message = "error: share is not an integer between [1,100]")
  #    }
  #  } else {
  #    res <- list(status = "fail", status_code = 1007, message = "error: share must be a number between [1,100]")
  #  }
  #}

  if (is.numeric(amount)) {
    if (amount > 0) { amount <- round(amount, 2); url <- paste0(url, "&amount=", amount) } 
    else { res <- list(status = "fail", error_code = 1009, message = "The specified amount parameter must be a number > 0")}
  } 
  else { res <- list(status = "fail", error_code = 1011, message = "The specified amount parameter is not numeric") } 
  

  # Perform the POST request
  if (res$status == "success") {
    response <- POST(url)
    content_response <- content(response, "text")
    parsed_response <- fromJSON(content_response)
  } else {
    parsed_response <- res
  }

  return(parsed_response)
}

pr$handle(
  "POST",
  "/borrow",
  borrowHandler,
  comment = "Allows managers to borrow assets from lending protocols within a specific pool, based on the specified protocol, network, and asset. You can define the platform (e.g., AAVE or COMPOUND) and choose a fixed amount to borrow. Be cautious as borrowing too much is risky and can result in liqudations."
)

