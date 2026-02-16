source("~/infinitetrading/src/db.R")
library(httr)

# Function to make the GET request
make_request <- function(side) {
  url <- "https://api.infinitetrading.io/setBot"
  params <- list(
    apiKey = "ae8db907aa5f561fa5720aeed5d0371d8c576f9a4fc94e3f6e445b5501ee5d016342fa993f5076bb019022e808e9f4236e14328996133908a59d1792a3b409ee",
    protocol = "dhedge",
    pool = "0x37849922d4b071254e25aa036a94442b059fdb60",
    network = "optimism",
    pair = "WBTC-USDC",
    side = side,
    threshold = 1,
    max_usd = 10000000,
    slippage = 1,
    share = 100,
    platform = "uniswapV3"
  )
 headers <- c('accept' = 'application/json')
  # Attempt the GET request
  response <- tryCatch({
   POST(url, body = params, encode ="json",add_headers(headers))
  }, error = function(e) {
    print(paste("Request failed:", e$message))
    NULL
  })
  if (is.null(response)) {
    print("API did not respond, retrying in 10 minutes.")
    Sys.sleep(600)  # Wait for 10 minutes (600 seconds)
    return(make_request())  # Retry the request
  } else if (status_code(response) >= 400) {
    print(paste("HTTP error:", status_code(response)))
    return(NULL)
  } else {
    print("Request successful")
    return(content(response, "text"))
  }
}
side = "hold"
while (1) { 
	prob = get_probabilities("ZeusBTC_6h-BTC-USD",candle_close=FALSE)
	if (prob >= 0.50) { side = "long" }
	else if (prob < 0.10) { side = "neutral" }
	else { side = "hold" }
	result <- make_request(side=side)
	print(result)
	Sys.sleep(60)
}
