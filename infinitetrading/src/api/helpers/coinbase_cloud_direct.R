get_coinbase_cloud_balance_direct <- function(api_key, secret) {
    require(httr)
    require(jsonlite)
    require(openssl)
    
    # Coinbase Cloud API endpoint
    base_url <- "https://api.coinbase.com"
    
    # Generate JWT token for authentication
    tryCatch({
        # For Cloud API, the api_key format is: organizations/{org_id}/apiKeys/{key_id}
        # Extract key_id from the api_key
        key_id <- sub(".*apiKeys/", "", api_key)
        key_name <- api_key
        
        # Create JWT header
        header <- list(
            alg = "ES256",
            kid = key_name,
            nonce = as.character(as.integer(Sys.time()))
        )
        
        # Create JWT payload
        payload <- list(
            sub = key_name,
            iss = "coinbase-cloud",
            nbf = as.integer(Sys.time()),
            exp = as.integer(Sys.time()) + 120,  # 2 minutes
            aud = list("retail_rest_api_proxy")
        )
        
        # The secret is the private key in PEM format
        # Sign the JWT
        header_json <- toJSON(header, auto_unbox = TRUE)
        payload_json <- toJSON(payload, auto_unbox = TRUE)
        
        header_b64 <- base64_urlencode(charToRaw(header_json))
        payload_b64 <- base64_urlencode(charToRaw(payload_json))
        
        message <- paste0(header_b64, ".", payload_b64)
        
        # Use the secret (private key) to sign
        # The secret should be in PEM format
        private_key <- read_key(secret)
        signature <- signature_create(charToRaw(message), key = private_key, hash = sha256)
        signature_b64 <- base64_urlencode(signature)
        
        jwt <- paste0(message, ".", signature_b64)
        
        # Make API request to get accounts
        response <- GET(
            paste0(base_url, "/api/v3/brokerage/accounts"),
            add_headers(
                Authorization = paste("Bearer", jwt),
                "Content-Type" = "application/json"
            )
        )
        
        if (status_code(response) == 200) {
            accounts <- content(response, as = "parsed")
            
            # Process accounts to extract balances
            balances <- list()
            total_usd <- 0
            
            if (!is.null(accounts$accounts)) {
                for (acc in accounts$accounts) {
                    currency <- acc$currency
                    balance <- as.numeric(acc$available_balance$value)
                    
                    if (!is.na(balance) && balance > 0) {
                        balances[[currency]] <- balance
                        
                        # Try to get USD value
                        if (currency == "USD" || currency == "USDC" || currency == "USDT") {
                            total_usd <- total_usd + balance
                        } else {
                            # Fetch price from Coinbase
                            price_resp <- tryCatch({
                                GET(paste0(base_url, "/api/v3/brokerage/products/", currency, "-USD"))
                            }, error = function(e) NULL)
                            
                            if (!is.null(price_resp) && status_code(price_resp) == 200) {
                                product <- content(price_resp)
                                price <- as.numeric(product$price)
                                if (!is.na(price)) {
                                    total_usd <- total_usd + (balance * price)
                                }
                            }
                        }
                    }
                }
            }
            
            return(list(
                success = TRUE,
                balances = balances,
                total_usd = total_usd
            ))
        } else {
            cat(sprintf("❌ API request failed: %d\n", status_code(response)))
            cat(sprintf("Response: %s\n", content(response, as = "text")))
            return(list(success = FALSE, balances = list(), total_usd = 0))
        }
        
    }, error = function(e) {
        cat(sprintf("❌ Error in direct API call: %s\n", e$message))
        return(list(success = FALSE, balances = list(), total_usd = 0))
    })
}
