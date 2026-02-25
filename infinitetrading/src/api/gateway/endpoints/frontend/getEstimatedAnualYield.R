######################################################################
#
#* @response 200 Returns the estimated anual yield for a specified pool
#* @response 500 Internal server error
#* @tag APY
#* @get /getEstimatedAnualYield
#
######################################################################


getEstimatedAnualYieldHandler <- function(pool,apiKey) {
    pool = tolower(pool)
    if (!isValidEthereumAddress(pool)) { return(list(status="fail",message="Invalid pool address")) }
    response <- POST(paste0(pep,"getEstimatedAnualYield?&pool=",pool,"&apiKey=",apiKey)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getEstimatedAnualYield",getEstimatedAnualYieldHandler,comment="This endpoint returns the estimated anual yield for a specific yield pool")
