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
    response_content <- content(response, "text")
    response_status <- status_code(response)
    cat("Response status:", response_status, "| Content:", response_content, "\n")
    
    parsed_response <- fromJSON(response_content)
    if (response_status == 200 || response_status == 201) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        # Check if response is numeric (price) or NULL (error)
        if (is.numeric(parsed_response) && !is.na(parsed_response)) {
            return(list(status="success", status_code=200, price=parsed_response))
        } else {
            return(list(status="fail", status_code=404, message="Invalid exchange or pair, price not available"))
        }
    }
    else { 
        cat("Error response - Status:", response_status, "\n")
        return(list(status="fail", status_code=response_status, message="Internal server error")) 
    }
}

pr$handle("GET","/getTicks",getTicksHandler,comment="This endpoint fetch candles (internal use, closed to the public for now) gives you coinbase: BTC-USD, ETH-USD, VELO-USD, POL-USD, OP-USD, SOL-USD, LINK-USD, ARB-USD, AERO-USD")
