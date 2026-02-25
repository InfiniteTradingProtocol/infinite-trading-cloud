######################################################################
#
#* @response 200 Returns the newly created gas wallet information including address, private key, and API key
#* @response 500 Internal server error
#* @tag Wallet
#* @get /createGasWallet
#
######################################################################

getCandlesHandler <- function(exchange="coinbase",timeframe="6h",pair="BTC-USD",bars_back=200,apiKey) {
    response <- POST(paste0(pep,"getCandles?&exchange=",tolower(exchange),"&timeframe=",timeframe,"&apiKey=",apiKey,"&pair=",pair,"&bars_back=",bars_back)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getCandles",getCandlesHandler,comment="This endpoint fetch candles (internal use, close it to the public for now) gives you coinbase: BTC-USD 6h, ETH-USD 6h, VELO-USD 6h, POL-USD 6h, OP-USD 6h, SOL-USD 6h, LINK-USD 6h, ARB-USD 6h, AERO-USD 6h")
