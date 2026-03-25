##########################################################################
# Register CEX Subaccount
#
#* @param manager The manager wallet address
#* @param gas_wallet_api_key The gas wallet API key for authentication
#* @param exchange The exchange name (coinbase, binance, okx, etc)
#* @param subaccount_name A user-friendly name for this subaccount
#* @param cex_api_key The CEX exchange API key
#* @param cex_secret The CEX exchange secret
#* @param cex_passphrase The CEX exchange passphrase (optional)
#* @param settings JSON object with additional settings (optional)
#* @param signature Wallet signature for authentication
#* @response 200 Returns success with subaccount_id
#* @response 400 Bad request
#* @response 401 Invalid signature
#* @response 500 Internal server error
#* @tag CEX
#* @post /registerCEXSubaccount
##########################################################################

registerCEXSubaccountHandler <- function(manager, gas_wallet_api_key, exchange, subaccount_name, 
                                          cex_api_key, cex_secret, cex_passphrase = "", 
                                          settings = "", signature = NULL) {
    tryCatch({
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        manager <- tolower(manager)
        
        if (is.null(manager) || manager == "") {
            return(list(status = "fail", status_code = 400, message = "manager is required"))
        }
        if (is.null(gas_wallet_api_key) || gas_wallet_api_key == "") {
            return(list(status = "fail", status_code = 400, message = "gas_wallet_api_key is required"))
        }
        if (is.null(signature) || signature == "") {
            return(list(status = "fail", status_code = 400, message = "signature is required"))
        }
        
        url <- paste0(
            pep, "registerCEXSubaccount",
            "?manager=", URLencode(manager, reserved = TRUE),
            "&gas_wallet_api_key=", URLencode(gas_wallet_api_key, reserved = TRUE),
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&cex_api_key=", URLencode(cex_api_key, reserved = TRUE),
            "&cex_secret=", URLencode(cex_secret, reserved = TRUE),
            "&cex_passphrase=", URLencode(cex_passphrase, reserved = TRUE),
            "&settings=", URLencode(settings, reserved = TRUE),
            "&signature=", URLencode(signature, reserved = TRUE)
        )
        
        response <- httr::POST(url)
        response_content <- httr::content(response, "text", encoding = "UTF-8")
        parsed_response <- jsonlite::fromJSON(response_content)
        
        return(parsed_response)
        
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, message = paste("Error:", e$message)))
    })
}

pr$handle("POST", "/registerCEXSubaccount", registerCEXSubaccountHandler, 
          comment = "Register a new CEX subaccount with encrypted credentials")
