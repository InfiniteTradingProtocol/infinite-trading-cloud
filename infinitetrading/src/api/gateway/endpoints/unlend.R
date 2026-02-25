##########################################################################
#
#* @param apiKey The API key for authentication
#* @param protocol The protocol to use
#* @param pool The pool to target
#* @param network The network to use
#* @param asset The asset to remove from lending (name or contract: Example: USDC or USDC contract address on that network)
#* @param share The share of the available balance on the specified asset to lend (default 100 to lend everything available)
#* @param amount This is the amount of the specified asset to unlend (optional, if you use share this will be ignored)
#* @param platform The platform to use (default is AAVE)
#* @response 200 Returns the result of the repay transaction.
#* @response 400 Bad request
#* @response 500 Internal server error
#* @tag unlend
#* @post /unlend
#
##########################################################################

unlendHandler = function(apiKey,protocol="dhedge",pool,network,asset,amount,platform="AAVE") {
	protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = tolower(platform)
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
	url <- paste0(pep,"unlend?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)

	#I NEED TO BE ABLE TO KNOW HOW MUCH OF THAT ASSET HAS BEEN LENDED TO USE 'SHARE' 

	#if (!is.null(share)) { 
	#	if (!is.na(share) && is.numeric(share)) {
        #        	if (share >=1 && share <= 100) { share = round(share); url = paste0(url,"&share=",share) }
        #        	else { res = list(status="fail",status_code=1007,message="error: share is not an integer between [1,100]") }
        # 	}
        # 	else { res = list(status="fail",status_code=1007,message="error: share must be a number between [1,100]") }
	#}
	amount = as.numeric(amount)
	if (!is.null(amount) && !is.na(amount)) {
	       if (amount > 0) { amount = round(amount,2); url = paste0(url,"&amount=",amount) }
               else { res = list(status="fail",error_code=1009,message="The speficied amount parameter must be a number > 0") }
        }
	else { res = list(status="fail",error_code=1011,message="The specified amount parameter is not numeric") }

	#else if (!is.numeric(amount) && !is.null(amount)) { res = list(status="fail",error_code=1011,message="The specified amount parameter is not numeric") } 

	# Perform the POST request
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
  "/unlend",
  unlendHandler,
  comment = "Allows managers to remove money from lending from a specific pool, protocol, network, and asset. You may specify the platform (e.g., AAVE), and choose a fixed amount. For example, if you want to unlend USDC and have $1,000 in lending, set amount = 10000 and it will remove from lending $1000."
)
  
