######################################################################
#
#* @response 200 Returns the gas multiplier for the API usage
#* @response 500 Internal server error
#* @tag Gas Fee
#* @get /getGasMultiplier
#
######################################################################


getGasMultiplierHandler <- function(apiKey) {
    response <- POST(paste0(pep,"getGasMultiplier?apiKey=",apiKey)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getGasMultiplier",getGasMultiplierHandler,comment="This endpoint returns the gas fee multiplier that users must pay on each trade using when they use this API. This value is multiplied by the transaction gas cost and charged to users as a service fee.")
