##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param asset The asset to repair (name or contract: Example: USDC or USDC contract address on that network)
#* @param share The share of the available balance on the specified asset to repay (default 100 to repay everything available)
#* @param amount This is the amount of the specified asset to repay (optional, if you use share this will be ignored)
#* @param platform The platform to use (default is AAVE)
#* @response 200 Returns the result of the repay transaction.
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag repay
#* @get /repay
#
##########################################################################

repayHandler = function(apiKey,protocol="dhedge",pool,network,asset,share=100,amount=0,platform="AAVE") {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
	url <- paste0(pep,"repay?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)

	if (!is.null(share)) { 
		if (!is.na(share) && is.numeric(share)) {
                	if (share >=1 && share <= 100) { share = round(share); url = paste0(url,"&share=",share) }
                	else { res = list(status="fail",status_code=1007,message="error: share is not an integer between [1,100]") }
        	}
        	else { res = list(status="fail",status_code=1007,message="error: share must be a number between [1,100]") }
	}
	if (is.numeric(amount)) {
	       if (amount > 0) { amount = round(amount,2); url = paste0(url,"&amount=",amount) }
               else if (is.null(share)) { res = list(status="fail",error_code=1009,message="The speficied amount parameter must be a number > 0") }
        }
	else if (is.null(share)) { res = list(status="fail",error_code=1011,message="The specified amount parameter is not numeric") }
	else if (!is.numeric(amount) && !is.null(amount)) { res = list(status="fail",error_code=1011,message="The specified amount parameter is not numeric") } 

	# Perform the POST request
        
	if (res$status == "success") { response <- POST(url); content_response = content(response,"text"); parsed_response <- fromJSON(content_response) }
        else { parsed_response = res } 
        return(parsed_response)
}
pr$handle(
  "POST",
  "/repay",
  repayHandler,
  comment = "Allows managers to repay debt on lending protocols within a specific pool, protocol, network, and asset. You may specify the platform (e.g., AAVE or COMPOUND), and choose either a repayment share or a fixed amount. For example, if you borrowed USDC and have $1,000 in your wallet, setting share = 10 will repay $100. Alternatively, setting amount = 100 will repay $100 directly. Note: if both are provided, the share parameter takes precedence and the amount will be ignored."
)
  
