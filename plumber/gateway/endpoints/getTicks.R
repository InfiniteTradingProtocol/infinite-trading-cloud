######################################################################
#
#* @response 200 Returns the price tick for a specific pair
#* @response 500 Internal server error
#* @tag Ticks
#* @get /getTicks
#
######################################################################

getTicksHandler <- function(exchange="coinbase",pair="BTC-USD",apiKey) {
    response <- POST(paste0(pep,"getTicks?&exchange=",tolower(exchange),"&apiKey=",apiKey,"&pair=",pair)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 201) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getTicks",getTicksHandler,comment="This endpoint fetch candles (internal use, closed to the public for now) gives you coinbase: BTC-USD, ETH-USD, VELO-USD, POL-USD, OP-USD, SOL-USD, LINK-USD, ARB-USD, AERO-USD")
