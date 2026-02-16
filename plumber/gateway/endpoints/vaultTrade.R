#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param from asset to sell
#* @param to asset to buy
#* @param amount The maximum USD amount to buy (optional) (default is 10,000,000)
#* @param slippage The slippage percentage (default is 1)
#* @param share The share percentage (default is 100)
#* @param platform The platform to use (default is odos)
#* @response 200 Returns the result of the trade request
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag managers
#* @post /vaultTrade

vaultTradeHandler <- function(network="optimism",protocol="dhedge",platform="odos",apiKey,pool,from,to,slippage=0.5, share=100, amount=NA) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") { return(check) }
        if (!is.na(amount) && !is.null(amount)) { amount = as.numeric(amount) }
        if (is.null(amount)) { amount = NA }
	if (is.null(share)) { share = NA }
	slippage = as.numeric(slippage); share = as.numeric(share);
	res = c(); res$status = "success"
	if (!is.na(share)) {
                if (share >=1 && share <= 100) { share = round(share) }
                else { res = list(status="fail",status_code=1007,message="error: share is not an integer between [1,100]") }
        }
        else { res = list(status="fail",status_code=1007,message="error: share is not an integer between [1,100]") }
        url <- paste0(pep,"vaultTrade?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&from=",from,"&to=",to,"&slippage=",slippage,"&share=",share,"&platform=",platform)
	if (!is.na(amount)) url = paste0(url,"&amount=",amount)
	# Perform the POST request
	print(paste0("query url: ",url))
        masked_api = mask_api(apiKey)
	if (res$status == "success") { response <- GET(url); content_response = content(response,"text"); parsed_response <- fromJSON(content_response) }
        else { parsed_response = res; content_response = res }
        msg = paste0(res$status," vaultTrade invoked by apiKey: ",masked_api, " / pool: ",pool," / protocol: ", protocol, " / network: ",network,"/ from: ", from,"/ to: ",to," / amount:",amount," / slippapge: ",slippage," / share: ",share," / platform: ",platform," / response: ",content_response)
        print(msg)
	return(parsed_response)
}

pr$handle("POST","/vaultTrade",vaultTradeHandler, comment="This endpoint is used to execute trades inside a specific pool on the specified protocol, network and for the specified asset. You can also specify the platform, slippage,share or amount for the trading. By default amount is NA, if amount is specified it will ignore the share parameter. If the amount specified is bigger than the vault balance it will use as the amount the max quantity available from the vauls." )
