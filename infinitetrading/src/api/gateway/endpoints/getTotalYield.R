######################################################################
#
#* @response 200 Returns the total yield for a specified pool
#* @response 500 Internal server error
#* @tag Yield
#* @get /getTotalYield
#
######################################################################


getTotalYieldHandler <- function(pool,apiKey) {
    pool = tolower(pool)
    if (!isValidEthereumAddress(pool)) { return(list(status="fail",message="Invalid pool address")) }
    response <- POST(paste0(pep,"getTotalYield?&pool=",pool,"&apiKey=",apiKey)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getTotalYield",getTotalYieldHandler,comment="This endpoint returns the total yield for a specific yield pool")
