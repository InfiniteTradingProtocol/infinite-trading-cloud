########################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param assets A string of assets separated by "-"
#* @param allocations A string of allocations separated by "-"
#* @param lower_thresholds A string of lower thresholds separated by "-"
#* @param upper_thresholds A string of upper thresholds separated by "-"
#* @param slippages A string of slippages separated by "-"
#* @param max_usd The maximum USD amount
#* @param platform The platform to use
#* @response 200 Returns the result of the allocations setting
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag Allocations
#* @get /setAllocations
#
#######################################################

setAllocationsHandler = function(apiKey,protocol="dhedge",pool,network,assets,allocations,lower_thresholds,upper_thresholds,slippages,max_usd,platform="uniswapV3") {
    protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); assets=toupper(assets);
    check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
    if (check$status == "fail") return(check)
    assets_vector = unlist(strsplit(assets, "-"))
    allocations_vector = as.numeric(unlist(strsplit(allocations, "-")))
    slippages_vector =  as.numeric(unlist(strsplit(slippages, "-")))
    lower_thresholds_vector = as.numeric(unlist(strsplit(lower_thresholds, "-")))
    upper_thresholds_vector =  as.numeric(unlist(strsplit(upper_thresholds, "-")))
    n_assets = length(assets_vector)
    if (n_assets != length(allocations_vector) || n_assets != length(lower_thresholds_vector)|| n_assets!= length(upper_thresholds_vector)|| n_assets !=length(slippages)){ return(list(status="fail",status_code=400,"Bad request: the length of the assets must be the same as the length of the allocations, upper thresholds, lower thresholds and slippages")) }
    max_usd = as.numeric(max_usd)
    if (!all(!is.na(allocations_vector))) { return(list(status="fail",status_code=400,"Bad request: all allocations must be numeric")) }
    allocations_vector = round(allocations_vector,2)
    if (!all(!is.na(slippages_vector))) { return(list(status="fail",status_code=400,"Bad request: all slippages must be numeric")) }
    slippages_vector = round(slippages_vector,3)
    if (!all(!is.na(upper_thresholds_vector))) { return(list(status="fail",status_code=400,"Bad request: all upper_thresholds must be numeric")) }
    upper_thresholds_vector = round(upper_thresholds_vector,3)
    if (!all(!is.na(lower_thresholds_vector))) { return(list(status="fail",status_code=400,"Bad request: all lower_thresholds must be numeric")) }
    lower_thresholds_vector = round(lower_thresholds_vector,3)
    if (!all(upper_thresholds_vector >=0) || !all(upper_thresholds_vector <=100)) { return(list(status="fail",status_code=400,"Bad request: all upper_thresholds must be numbers between 0 and 100")) }
    if (!all(lower_thresholds_vector >=0) || !all(lower_thresholds_vector <=100)) { return(list(status="fail",status_code=400,"Bad request: all lower_thresholds must be numbers between 0 and 100")) }
    if (!all(allocations_vector >=0) || !all(allocations_vector <=100)) {  return(list(status="fail",status_code=400,"Bad request: all allocations must be numbers between 0 and 100")) }
    if (!is.numeric(max_usd) || max_usd <= 0) { return(list(status="fail",status_code=400,"Bad request: max_usd must be numeric and greater than 0")) }
    if (max_usd > 100000000) { return(list(status="fail",status_code=400,"Bad request: max_usd must be smaller or equal to $100,000,000")) }
    if (!all(slippages_vector >=0) || !all(slippages_vector <=100)) {  return(list(status="fail",status_code=400,"Bad request: slippages must be numbers between 0 and 100")) }
    url <- paste0(pep,"setAllocations?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&assets=",assets,"&allocations=",allocations,"&lower_thresholds=",lower_thresholds,"&upper_thresholds=",upper_thresholds,"&slippages=",slippages,"&max_usd=",max_usd,"&platform=",platform)
    # Perform the POST request`
    print(url)
    response <- POST(url)
    # Parse the JSON response
    response_content <- content(response, "text")
    parsed_response <- fromJSON(response_content)
    masked_api = mask_api(apiKey)
    if (status_code(response) == 200) { discord(msg=paste0("succes setAllocations invoked apiKey: ", masked_api, " / pool: ",pool," / protocol: ", protocol, " / assets: ",assets,"/ allocations", allocations,"/ upper_thresholds: ",upper_thresholds," / lower_thresholds: ",lower_thresholds," / response: ",response_content),channel="#api-logs",db=FALSE) }
    else { discord(msg=paste0("failed setAllocations invoked apiKey: ", masked_api , " / pool: ",pool," / protocol: ", protocol, " / assets: ",assets,"/ allocations", allocations,"/ upper_thresholds: ",upper_thresholds," / lower_thresholds: ",lower_thresholds," / response: ",response_content),channel="#api-logs",db=FALSE) }
    return(parsed_response)
}

pr$handle("GET","/setAllocations",setAllocationsHandler,comment="This endpoint is used to set the allocations of your indices and your rebalancing thresholds for a pool on the specified network and protocol.")
