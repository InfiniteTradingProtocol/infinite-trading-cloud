#* @tag managers
#* @param network:string The Ethereum Layer 2 network to use (Base, Optimism, Polygon, Arbitrum)
#* @param protocol:string The protocol to use (only one available for now dHEDGE)
#* @param asset:string The asset to approve (Example: USDC or USDC Contract address)
#* @param platform:string The platform where the trade or lending/borrowing will be executed (recommended for swaps: odos, lending/borrowing: aave)
#* @post /approve
#* @response 200 approve status

approveHandler = function(network, pool, apiKey, asset, protocol="dhedge", platform="odos") {
  network  = tolower(network)
  protocol = tolower(protocol)
  platform = tolower(platform)

  check = basic_check(network=network, protocol=protocol, pool=pool, apiKey=apiKey)
  if (check$status == "fail") return(check)

  url = paste0(
    pep, "approve?network=", network,
    "&protocol=", protocol,
    "&pool=", pool,
    "&apiKey=", apiKey,
    "&asset=", utils::URLencode(asset, reserved = TRUE),
    "&platform=", platform
  )
  print("gateway approve invoked for this token:")
  print(asset)
  # ---- async: run the slow call in a worker and return the promise ----
  future_promise({
    response <- httr::POST(url)                   # you can add httr::timeout(60) if you like
    response_content <- httr::content(response, "text", encoding = "UTF-8")
    parsed_response <- jsonlite::fromJSON(response_content)
    print(parsed_response)
    parsed_response
  }) %...!% (function(e) {
    # minimal error payload consistent with your current style
    list(status="fail", status_code=502, message=paste("Gateway error:", conditionMessage(e)))
  })
}

# unchanged registration
pr$handle("POST","/approve", approveHandler,
  comment="This endpoint is used to approve the assets to be trade or used for borrowing/lending within the pool for the gas wallet. If you plan to go also go short, You need to enable BTC1XBEAR or ETH1XBEAR (only available on Optimism,Arbitrum) to be able to go short."
)

