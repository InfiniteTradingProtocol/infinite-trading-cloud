# create a sub-router
aaveV3 <- Plumber$new()

aaveV3$handle("POST","/lend",
    function(apiKey,protocol="dhedge",pool,network,asset,share=100,amount=0) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = "aavev3"
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
    ,
    comment = "Allows managers to lend money on lending protocols within a specific pool, protocol, network, and asset. You may specify the platform (e.g., AAVE), and choose either a lend share (percentage of the total in the vault) or a fixed amount. For example, if you want to lend USDC and have $1,000 in your wallet, setting share = 10 will lend $100. Alternatively, setting amount = 100 will lend $100 USDC directly. Note: if both are provided, the share parameter takes precedence and the amount will be ignored."
)

aaveV3$handle("GET", "/getBorrowed",
	function(apiKey,protocol,network,pool,asset) {
        	protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); 
        	check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        	if (check$status == "fail") return(check)
        	res <- list(status="success")
        	url <- paste0(pep,"getBorrowed?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset)
	        # Perform the POST request
        	if (res$status == "success") {
                	response <- POST(url)
                	txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
               		if (status_code(response) == 200) {
                        	parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
                        	return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
                	}
                	return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
       	 	}
        	return(res)
	},
	comment="Get total borrowed amounts on Aave v3 for a given protocol, network,pool and asset."
)

aaveV3$handle("GET", "/getSupplied",
        function(apiKey,protocol,network,pool,asset) {
                protocol=tolower(protocol); pool = tolower(pool); network = tolower(network);
                check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
                if (check$status == "fail") return(check)
                res <- list(status="success")
                url <- paste0(pep,"getSupplied?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset)
                # Perform the POST request
                if (res$status == "success") {
                        response <- POST(url)
                        txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
                        if (status_code(response) == 200) {
                                parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
                                return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
                        }
                        return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
                }
                return(res)
        },
        comment="Get total borrowed amounts on Aave v3 for a given protocol, network,pool and asset."
)

aaveV3$handle("POST","/unlend",
    function(apiKey,protocol="dhedge",pool,network,asset,share=100,amount=0) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = "aavev3"
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
        res <- list(status="success")
        url <- paste0(pep,"unlend?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)
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
                return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
        }
        return(res)
    },
    comment = "Allows managers to withdraw (unlend) assets from Aave v3 lending within a specific pool, protocol, network, and asset. You may specify either a share (percentage of supplied balance) or a fixed amount."
)

aaveV3$handle("POST","/borrow",
    function(apiKey,protocol="dhedge",pool,network,asset,amount=0) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = "aavev3"
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
        res <- list(status="success")
        url <- paste0(pep,"borrow?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)
        if (is.numeric(amount) && amount > 0) { amount = round(amount,2); url = paste0(url,"&amount=",amount) }
        else if (is.null(amount) || amount <= 0) { res = list(status="fail",error_code=1009,message="Please specify a valid amount (amount>0) parameter.") }
        # Perform the POST request
        if (res$status == "success") {
            response <- POST(url)
            txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
            if (status_code(response) == 200) {
                parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
                return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
            }
            return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
        }
        return(res)
    },
    comment = "Allows managers to borrow assets from Aave v3 within a specific pool, protocol, network, and asset. You may specify a fixed amount to borrow. Be cautious as borrowing too much is risky and can result in liquidations."
)

aaveV3$handle("POST","/repay",
    function(apiKey,protocol="dhedge",pool,network,asset,share=100,amount=0) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = "aavev3"
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
        res <- list(status="success")
        url <- paste0(pep,"repay?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&asset=",asset,"&platform=",platform)
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
                return(list(status = "fail",status_code = status_code(response),message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
        }
        return(res)
    },
    comment = "Allows managers to repay borrowed assets to Aave v3 within a specific pool, protocol, network, and asset. You may specify either a share (percentage of borrowed amount) or a fixed amount to repay."
)

aaveV3$handle("GET","/getPoolData",
    function(apiKey,protocol="dhedge",pool,network) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); 
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
        url <- paste0(pep,"getPoolAaveData?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network)
        # Perform the POST request
        response <- POST(url)
        content_response <- content(response,"text")
        parsed_response <- fromJSON(content_response)
        return(parsed_response)
    },
    comment = "Retrieves the complete AAVE v3 account data for the specified pool, including health factor, total collateral, total debt, and available borrowing power."
)

aaveV3$handle("GET","/getHealthFactor",
    function(apiKey,protocol="dhedge",pool,network) {
        protocol=tolower(protocol); pool = tolower(pool); network = tolower(network); platform = "aavev3"
        check = basic_check(network=network,protocol=protocol,pool=pool,apiKey=apiKey)
        if (check$status == "fail") return(check)
        url <- paste0(pep,"getHealthFactor?apiKey=",apiKey,"&protocol=",protocol,"&pool=",pool,"&network=",network,"&platform=",platform)
        # Perform the POST request
        response <- POST(url)
        content_response <- content(response,"text")
        parsed_response <- fromJSON(content_response)
        return(parsed_response)
    },
    comment = "Retrieves the health factor for the AAVE v3 position. Health factor below 1.0 indicates risk of liquidation."
)

# mount onto the main router (relies on `pr` being in scope when sourced)
pr$mount("/aaveV3", aaveV3)

