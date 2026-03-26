######################################################################
#
#* @response 200 Returns the total yield for all pools.
#* @response 500 Internal server error
#* @tag Yield
#* @get /getAllYields
#
######################################################################


getAllYieldsHandler <- function(apiKey) {
    response <- POST(paste0(pep,"getAllYields?apiKey=",apiKey)); 
    response_content <- content(response, "text"); parsed_response <- fromJSON(response_content)
    if (status_code(response) == 200) {
        if(is.character(parsed_response)) parsed_response <- fromJSON(parsed_response)
        parsed_response
    }
    else { print(parsed_response); return(parsed_response) }
}

pr$handle("GET","/getAllYields",getAllYieldsHandler,comment="This endpoint returns the yield information for all ITP yield pools available (internal use for our front-end)")
