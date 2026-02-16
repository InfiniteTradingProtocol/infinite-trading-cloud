##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param network The network to use
#* @param pool The pool to target
#* @response 200 Returns the result of the bot deletion
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @delete /managers/deleteBot
#
##########################################################################

deleteBotHandler <- function(apiKey = NULL, protocol = "dhedge", network = NULL, pool = NULL) {
  protocol <- tolower(protocol)
  pool     <- tolower(pool)
  network  <- tolower(network)

  # === Validate required params ===
  required_params <- list(apiKey = apiKey, network = network, pool = pool)
  missing <- names(required_params)[sapply(required_params, function(x) is.null(x) || x == "")]
  if (length(missing) > 0) {
    return(list(
      status = "fail",
      status_code = 400,
      message = paste("Missing required parameters:", paste(missing, collapse = ", "))
    ))
  }

  # === Run basic validation ===
  check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
  if (!is.null(check$status) && check$status == "fail") {
    return(list(
      status = "fail",
      status_code = 400,
      message = check$message
    ))
  }

  # === Build the request URL ===
  url <- paste0(pep, "deleteBot?",
                "apiKey=", apiKey,
                "&protocol=", protocol,
                "&pool=", pool,
                "&network=", network)

  # === Make the request safely ===
  result <- tryCatch({
    response <- httr::POST(url)
    code <- httr::status_code(response)
    text <- httr::content(response, "text", encoding = "UTF-8")
    parsed <- tryCatch(jsonlite::fromJSON(text), error = function(e) list(message = text))

    msg <- if (!is.null(parsed$message)) parsed$message else text

    if (code >= 200 && code < 300) {
      list(status = "success", status_code = code, message = msg)
    } else {
      list(status = "fail", status_code = code, message = msg)
    }
  }, error = function(e) {
    list(status = "fail", status_code = 500, message = paste("Internal server error:", e$message))
  })

  return(result)
}

pr$handle("DELETE","/deleteBot",deleteBotHandler, comment="This endpoint is used to turn off the trading bot.")
