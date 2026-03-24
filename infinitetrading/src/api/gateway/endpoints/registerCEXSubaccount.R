##########################################################################
# Register CEX Subaccount
#
#* @param apiKey The API key for authentication
#* @param exchange The exchange name (coinbase, binance, okx, etc)
#* @param subaccount_name A user-friendly name for this subaccount
#* @param cex_api_key The CEX exchange API key
#* @param cex_secret The CEX exchange secret
#* @param cex_passphrase The CEX exchange passphrase (optional, for exchanges that require it)
#* @param settings JSON object with additional settings (optional)
#* @response 200 Returns success with subaccount_id
#* @response 400 Bad request - missing parameters
#* @response 500 Internal server error
#* @tag CEX
#* @post /registerCEXSubaccount
#
##########################################################################

registerCEXSubaccountHandler <- function(apiKey, exchange, subaccount_name, cex_api_key, cex_secret, 
                                   cex_passphrase = "", settings = "") {
    tryCatch({
        # Validate API key first
        if (!isValidAPIKey(apiKey)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        # Sanitize inputs - remove dangerous characters
        cex_api_key <- gsub("[^a-zA-Z0-9_-]", "", cex_api_key)
        cex_secret <- gsub("[^a-zA-Z0-9_/-]", "", cex_secret)
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        
        # Validate required parameters
        if (is.null(cex_api_key) || cex_api_key == "") {
            return(list(status = "fail", status_code = 400, message = "cex_api_key is required"))
        }
        if (is.null(cex_secret) || cex_secret == "") {
            return(list(status = "fail", status_code = 400, message = "cex_secret is required"))
        }
        if (is.null(exchange) || exchange == "") {
            return(list(status = "fail", status_code = 400, message = "exchange is required"))
        }
        if (is.null(subaccount_name) || subaccount_name == "") {
            return(list(status = "fail", status_code = 400, message = "subaccount_name is required"))
        }
        
        # Validate API key format (alphanumeric, dash, underscore, 10-100 chars)
        if (nchar(cex_api_key) < 10 || nchar(cex_api_key) > 200) {
            return(list(status = "fail", status_code = 400, message = "Invalid API key format"))
        }
        
        # Validate secret format (alphanumeric, dash, slash, 10-200 chars)
        if (nchar(cex_secret) < 10 || nchar(cex_secret) > 200) {
            return(list(status = "fail", status_code = 400, message = "Invalid secret format"))
        }
        
        # Validate subaccount name length
        if (nchar(subaccount_name) > 100) {
            return(list(status = "fail", status_code = 400, message = "Subaccount name too long (max 100 chars)"))
        }
        
        # Validate exchange name
        valid_exchanges <- c("coinbase", "binance", "okx", "kucoin", "bybit", "bitget", 
                            "kraken", "huobi", "gateio", "mexc")
        if (!(exchange %in% valid_exchanges)) {
            return(list(
                status = "fail", 
                status_code = 400, 
                message = paste("Invalid exchange. Supported:", paste(valid_exchanges, collapse = ", "))
            ))
        }
        
        # Validate passphrase if provided
        if (!is.null(cex_passphrase) && cex_passphrase != "") {
            cex_passphrase <- gsub("[^a-zA-Z0-9!@#$%^&*()_+-=]", "", cex_passphrase)
            if (nchar(cex_passphrase) > 100) {
                return(list(status = "fail", status_code = 400, message = "Passphrase too long (max 100 chars)"))
            }
        }
        
        # Validate settings JSON if provided
        settings_json <- ""
        if (!is.null(settings) && settings != "") {
            if (is.character(settings)) {
                tryCatch({
                    jsonlite::fromJSON(settings)
                    settings_json <- settings
                }, error = function(e) {
                    return(list(status = "fail", status_code = 400, message = "Invalid JSON format for settings"))
                })
            } else {
                settings_json <- jsonlite::toJSON(settings, auto_unbox = TRUE)
            }
        }
        
        # Build URL for Plumber API call
        url <- paste0(
            pep, 
            "registerCEXSubaccount",
            "?apiKey=", apiKey,
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&cex_api_key=", URLencode(cex_api_key, reserved = TRUE),
            "&cex_secret=", URLencode(cex_secret, reserved = TRUE)
        )
        
        if (!is.null(cex_passphrase) && cex_passphrase != "") {
            url <- paste0(url, "&cex_passphrase=", URLencode(cex_passphrase, reserved = TRUE))
        }
        
        if (settings_json != "") {
            url <- paste0(url, "&settings=", URLencode(settings_json, reserved = TRUE))
        }
        
        # Make POST request to Plumber API
        response <- POST(url)
        response_content <- content(response, "text", encoding = "UTF-8")
        parsed_response <- fromJSON(response_content)
        
        if (status_code(response) == 200) {
            return(list(
                status = "success",
                status_code = 200,
                message = "CEX subaccount registered successfully",
                subaccount_id = parsed_response$subaccount_id,
                exchange = exchange,
                subaccount_name = subaccount_name
            ))
        } else {
            return(list(
                status = "fail",
                status_code = status_code(response),
                message = parsed_response$message
            ))
        }
        
    }, error = function(e) {
        return(list(
            status = "fail",
            status_code = 500,
            message = paste("Error registering CEX subaccount:", e$message)
        ))
    })
}

pr$handle("POST", "/registerCEXSubaccount", registerCEXSubaccountHandler, 
          comment = "Register CEX subaccount credentials with encryption. Returns subaccount_id for future reference.")
