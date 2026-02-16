#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param pair The trading pair
#* @param side The side to set (long, short, hold, or neutral)
#* @param threshold The threshold for the strategy (default is 1)
#* @param max_usd The maximum USD amount (default is 10,000,000)
#* @param slippage The slippage percentage (default is 1)
#* @param share The share percentage (default is 100)
#* @param platform The platform to use (default is uniswapV3)
#* @response 200 Returns the result of setting the bot strategy
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @post /setBot
setBotHandler = function(apiKey,
                         protocol = "dhedge",
                         pool,
                         network,
                         pair,
                         side,
                         threshold = 1,
                         max_usd = 10000000,
                         slippage = 1,
                         share = 100,
                         platform = "odos",
			 lending=FALSE) {
  
  # Normalize case
  protocol <- tolower(protocol)
  pool <- tolower(pool)
  network <- tolower(network)
  side <- tolower(side)
  platform <- tolower(platform)
  if (is.null(lending) || !is.logical(lending)) { lending = FALSE }
  # API key check
  check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
  if (check$status == "fail") return(check)
  
  # Convert numeric inputs
  if (!is.null(max_usd)) {
    max_usd <- suppressWarnings(as.numeric(max_usd))
  }
  slippage <- suppressWarnings(as.numeric(slippage))
  share <- suppressWarnings(as.numeric(share))
  threshold <- suppressWarnings(as.numeric(threshold))
  # Validate 'side'
  if (!(side %in% c("hold", "neutral", "short", "long"))) {
    return(list(status = "fail", status_code = 1008, message = "The specified side must be one of: long, short, hold, or neutral."))
  }
  else if (side == "short")  {
	 return(list(status = "fail", status_code = 400, message ="Shorting is temporary disabled."))
	 if (network != "arbitrum" || network != "optimism") return(list(status = "fail", status_code = 400, message = "Shorts doesn't work on the specified network, use Arbitrum or Optimism to go short."))
  }
  # Validate 'threshold'
  if (!is.na(threshold)) {
    if (threshold >= 0 && threshold <= 100) {
      threshold <- round(threshold,2)
    } else {
      return(list(status = "fail", status_code = 400, message = "Threshold must be number in the range [0, 100]."))
    }
  } else {
    return(list(status = "fail", status_code = 400, message = "Threshold is not a valid number in the range [0, 100]."))
  }
  
  # Validate 'share'
  if (!is.na(share)) {
    if (share >= 1 && share <= 100) {
      share <- round(share,2)
    } else {
      return(list(status = "fail", status_code = 400, message = "Share must be a number in the range [1, 100]."))
    }
  } else {
    return(list(status = "fail", status_code = 400, message = "Share is not a valid number in the range [1, 100]."))
  }
  
  # Validate 'max_usd'
  if (!is.null(max_usd)) {
    if (is.na(max_usd)) {
      return(list(status = "fail", status_code = 400, message = "The specified max_usd is not numeric."))
    }
    if (max_usd <= 0) {
      return(list(status = "fail", status_code = 400, message = "The specified max_usd must be a number > 0."))
    }
    max_usd <- round(max_usd, 2)
  }
  
  # Build URL
  url <- paste0(pep, "setSide?",
                "apiKey=", apiKey,
                "&protocol=", protocol,
                "&pool=", pool,
                "&network=", network,
                "&pair=", pair,
                "&side=", side,
                "&threshold=", threshold,
                "&max_usd=", max_usd,
                "&slippage=", slippage,
                "&share=", share,
                "&platform=", platform,
  		"&lending=",lending	
  	)
  
  # Masked API key for logging
  masked_api <- mask_api(apiKey)
  
  # Perform POST request to /setSide
  response <- POST(url)
  content_response <- content(response, "text")
  
  parsed_response <- tryCatch({
    fromJSON(content_response)
  }, error = function(e) {
    list(status = "fail", status_code = 500, message = paste0("Error parsing response: ", content_response))
  })
  
  # Log message
  msg <- paste0(
    "setBot invoked | apiKey: ", masked_api,
    " / pool: ", pool,
    " / protocol: ", protocol,
    " / network: ", network,
    " / pair: ", pair,
    " / side: ", side,
    " / threshold: ", threshold,
    " / max_usd: ", max_usd,
    " / slippage: ", slippage,
    " / share: ", share,
    " / platform: ", platform,
    " / lending: ",lending,
    " / response: ", paste0(names(parsed_response), "=", unlist(parsed_response), collapse = ", ")
  )
  
  print(msg)
  #discord(msg = msg, channel = "#api-logs")
  send_telegram_text(msg)
  return(parsed_response)
}

pr$handle("POST","/setBot",setBotHandler, comment="This endpoint is used to set the sides of your tradingbot strategy on a specific pool, network and protocol. The sides are used by the tradebots to monitor and rebalance the pools according to the strategy. The sides can be long, short, hold or neutral. Long will buy everything on the vault, short will short everything, neutral will sell to USDC all positions and hold wont do anything with new deposits or current positions. Enable lending to allow the bot to deposit the token on the current side into AAVE V3 to earn yield while you hold. (Require AAVE V3 Enabled, Coming Soon)")
