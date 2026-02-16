library(httr)
source("~/infinitetrading/src/db.R")

# Function to make the GET request
make_request <- function(side) {
  base_url <- "https://api.infinitetrading.io/setBot"
  query_params <- sprintf("?apiKey=%s&protocol=%s&pool=%s&network=%s&pair=%s&side=%s&threshold=%d&max_usd=%d&slippage=%d&share=%d&platform=%s",
                          "ae8db907aa5f561fa5720aeed5d0371d8c576f9a4fc94e3f6e445b5501ee5d016342fa993f5076bb019022e808e9f4236e14328996133908a59d1792a3b409ee", # API Key
                          "dhedge",
                          "0x37849922d4b071254e25aa036a94442b059fdb60",
                          "optimism",
                          "WBTC-USDC",
                          side,
                          1,
                          10000000,
                          1,
                          100,
                          "uniswapV3")
  full_url <- paste0(base_url, query_params)
  headers <- add_headers('Accept' = 'application/json')

  # Attempt the GET request
  response <- tryCatch({
    GET(full_url, headers)
  }, error = function(e) {
    print(paste("Request failed:", e$message))
    NULL
  })

  if (is.null(response)) {
    print("API did not respond, retrying in 10 minutes.")
    Sys.sleep(600)  # Wait for 10 minutes (600 seconds)
    return(make_request(side))  # Retry the request
  } else if (status_code(response) >= 400) {
    print(paste("HTTP error:", status_code(response)))
    return(NULL)
  } else {
    print("Request successful")
    return(content(response, "text"))
  }
}

side = "hold"
old_side=side
while (TRUE) {
  prob = get_probabilities("ZeusBTC_6h-BTC-USD", candle_close=FALSE)
  if (prob >= 0.50) { side = "long" }
  else if (prob < 0.10) { side = "neutral" }
  else { side = "hold" }
  if (old_side != side) { 
	  result <- make_request(side = side)
	  old_side = side
  }
  print(result)
  Sys.sleep(60)
}

