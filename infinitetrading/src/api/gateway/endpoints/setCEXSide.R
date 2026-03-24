##########################################################################
# Set CEX Bot Side Configuration
#
#* @param apiKey The API key for authentication
#* @param exchange The exchange name (coinbase, binance, okx, etc)
#* @param subaccount_name The subaccount name
#* @param pair The trading pair (e.g. BTC-USD, ETH-USDT)
#* @param side The trading side: long, neutral, hold
#* @param max_usd Maximum USD to use for this bot (default: 100)
#* @param share Percentage of balance to use 0-100 (default: 100)
#* @param strategy Strategy name (e.g. crossover, ema-rsi) or 'custom' (default: custom)
#* @response 200 Returns success with bot_id
#* @response 400 Bad request - missing parameters
#* @response 404 Subaccount not found
#* @response 500 Internal server error
#* @tag CEX
#* @post /setCEXSide
#
##########################################################################

setCEXSideHandler <- function(apiKey, exchange, subaccount_name, pair, side, max_usd = "100", share = "100", strategy = "") {
    tryCatch({
        # Validate API key first
        if (!isValidAPIKey(apiKey)) {
            return(list(status = "fail", status_code = 400, message = "Invalid API Key"))
        }
        
        # Sanitize inputs - remove dangerous characters
        exchange <- gsub("[^a-zA-Z]", "", tolower(exchange))
        subaccount_name <- gsub("[^a-zA-Z0-9_ -]", "", subaccount_name)
        pair <- gsub("[^A-Z0-9-/]", "", toupper(pair))
        side <- gsub("[^a-z]", "", tolower(side))
        
        # Default to 'custom' strategy when manually setting side
        if (is.null(strategy) || strategy == "") {
            strategy <- "custom"
        } else {
            strategy <- gsub("[^a-zA-Z0-9_-]", "", tolower(strategy))
        }
        
        # Validate required parameters
        if (is.null(exchange) || exchange == "") {
            return(list(status = "fail", status_code = 400, message = "exchange is required"))
        }
        if (is.null(subaccount_name) || subaccount_name == "") {
            return(list(status = "fail", status_code = 400, message = "subaccount_name is required"))
        }
        if (is.null(pair) || pair == "") {
            return(list(status = "fail", status_code = 400, message = "pair is required"))
        }
        if (is.null(side) || side == "") {
            return(list(status = "fail", status_code = 400, message = "side is required"))
        }
        
        # Validate side
        if (!(side %in% c("long", "neutral", "hold"))) {
            return(list(
                status = "fail", 
                status_code = 400, 
                message = "Invalid side. Must be: long, neutral, or hold"
            ))
        }
        
        # Validate and sanitize max_usd
        max_usd_num <- suppressWarnings(as.numeric(max_usd))
        if (is.na(max_usd_num)) {
            return(list(status = "fail", status_code = 400, message = "max_usd must be numeric"))
        }
        if (max_usd_num < 10 || max_usd_num > 100000000) {
            return(list(status = "fail", status_code = 400, message = "max_usd must be between $10 and $100,000,000"))
        }
        
        # Validate and sanitize share
        share_num <- suppressWarnings(as.numeric(share))
        if (is.na(share_num)) {
            return(list(status = "fail", status_code = 400, message = "share must be numeric"))
        }
        if (share_num < 1 || share_num > 100) {
            return(list(status = "fail", status_code = 400, message = "share must be between 1 and 100"))
        }
        
        # Normalize pair format (BTC/USD -> BTC-USD)
        pair <- gsub("/", "-", pair)
        
        # Validate pair format (XXX-YYY or XXXX-YYYY)
        if (!grepl("^[A-Z]{2,10}-[A-Z]{2,10}$", pair)) {
            return(list(status = "fail", status_code = 400, message = "Invalid pair format. Use: BTC-USD, ETH-USDT, etc."))
        }
        
        # Build URL for Plumber API call
        url <- paste0(
            pep,
            "setCEXSide",
            "?apiKey=", apiKey,
            "&exchange=", exchange,
            "&subaccount_name=", URLencode(subaccount_name, reserved = TRUE),
            "&pair=", pair,
            "&side=", side,
            "&max_usd=", sprintf("%.2f", max_usd_num),
            "&share=", sprintf("%.2f", share_num),
            "&strategy=", strategy
        )
        
        # Make POST request to Plumber API
        response <- POST(url)
        response_content <- content(response, "text", encoding = "UTF-8")
        parsed_response <- fromJSON(response_content)
        
        if (status_code(response) == 200) {
            return(list(
                status = "success",
                status_code = 200,
                message = parsed_response$message,
                bot_id = parsed_response$bot_id,
                exchange = exchange,
                subaccount_name = subaccount_name,
                pair = pair,
                side = side,
                previous_side = parsed_response$previous_side,
                side_changed = parsed_response$side_changed,
                max_usd = max_usd_num,
                share = share_num
            ))
        } else{
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
            message = paste("Error setting CEX side:", e$message)
        ))
    })
}

pr$handle("POST", "/setCEXSide", setCEXSideHandler, 
          comment = "Set trading side for a CEX bot. Side changes trigger immediate trade execution on next cycle.")
