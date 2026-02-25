##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param asset The asset to lend (name or contract: Example: USDC or USDC contract address on that network)
#* @param share The share of the available balance on the specified asset to lend (default 100 to lend everything available)
#* @param amount This is the amount of the specified asset to leend (optional, if you use share this will be ignored)
#* @param platform The platform to use (default is AAVE)
#* @response 200 Returns the result of the repay transaction.
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag lend
#* @post /lend
#
##########################################################################

lendHandler = function(apiKey,protocol="dhedge",pool,network,asset,share=100,amount=0,platform="AAVE") {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
	res <- list(status="success")
	url <- paste0(pep,"lend?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)
	if (!is.null(share)) { share = as.numeric(share); }
	if (is.numeric(share)) { share = round(share,2) }
	if (!is.null(amount)) { amount = as.numeric(amount) }
	if (is.numeric(amount) && !is.na(amount)) { amount = round(amount,2) }

	if (!is.null(share) && !is.na(share)) { 
                if (share >0 && share <= 100) { url = paste0(url,"&share=",share) }
                else { res = list(status="fail",status_code=1007,message="error: share is not an integer between [1,100]") } 
	}
	if (is.numeric(amount) && amount > 0) { url = paste0(url,"&amount=",amount) }
        else if (is.null(share)) { res = list(status="fail",error_code=1009,message="Please specify a share or amount (amount>0) parameters.") }

	# Perform the POST request
	if (res$status == "success") {
    		response <- POST(url)
    		txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
    		if (status_code(response) == 200) {
       			parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
        		return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
    		}
    		return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)
    	))
	}
	return(res)        
}
pr$handle(
  "POST",
  "/lend",
  lendHandler,
  comment = "Allows managers to lend money on lending protocols within a specific pool, protocol, network, and asset. You may specify the platform (e.g., AAVE), and choose either a lend share (percentage of the total in the vault) or a fixed amount. For example, if you want to lend USDC and have $1,000 in your wallet, setting share = 10 will lend $100. Alternatively, setting amount = 100 will lend $100 USDC directly. Note: if both are provided, the share parameter takes precedence and the amount will be ignored."
)
  
