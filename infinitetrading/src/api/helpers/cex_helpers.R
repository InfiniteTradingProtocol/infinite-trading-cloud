###############################
# CEX Helper Functions        #
###############################

# Constants
CEX_MIN_GAS_BALANCE_USD <- 10.00
CEX_GAS_CHECK_INTERVAL <- 3600  # 1 hour in seconds
CEX_LOW_GAS_WARNING_USD <- 25.00

# Database wrapper functions for CEX operations
db_query <- function(query) {
    con <- db_con(use_pool = FALSE)  # Force direct connection
    on.exit({
        if (!is.null(con)) tryCatch(DBI::dbDisconnect(con), error = function(e) {})
    }, add = TRUE)
    
    result <- tryCatch({
        DBI::dbGetQuery(con, query)
    }, error = function(e) {
        stop(paste("Query error:", e$message))
    })
    return(result)
}

db_execute <- function(query) {
    con <- db_con(use_pool = FALSE)  # Force direct connection
    on.exit({
        if (!is.null(con)) tryCatch(DBI::dbDisconnect(con), error = function(e) {})
    }, add = TRUE)
    
    result <- tryCatch({
        DBI::dbExecute(con, query)
    }, error = function(e) {
        stop(paste("Execute error:", e$message))
    })
    return(result)
}

# Gas Wallet API Key encryption (DeFi standard: AES-256-CBC)
encrypt_gas_wallet_api_key <- function(api_key) {
    secure_encrypt(api_key, hexmode = TRUE)
}

decrypt_gas_wallet_api_key <- function(encrypted_key) {
    add_0x_prefix(secure_decrypt(encrypted_key))
}

# Validate gas wallet API key access to CEX subaccount
isValidCEXGasWalletKey <- function(gas_wallet_api_key, subaccount_name) {
    encrypted_key <- secure_encrypt(gas_wallet_api_key, hexmode = TRUE)
    result <- db_query(sprintf(
        "SELECT id FROM cex_subaccounts 
         WHERE encrypted_gas_wallet_api_key = '%s' 
         AND subaccount_name = '%s' 
         AND is_active = TRUE",
        encrypted_key, subaccount_name
    ))
    return(nrow(result) > 0)
}

# Get gas wallet address from API key
getGasWalletFromAPIKey <- function(gas_wallet_api_key) {
    encrypted_key <- secure_encrypt(gas_wallet_api_key, hexmode = TRUE)
    result <- db_query(sprintf(
        "SELECT wallet FROM associated_gas_wallets 
         WHERE encrypted_api_key = '%s'",
        encrypted_key
    ))
    if (nrow(result) > 0) return(result$wallet[1])
    return(NULL)
}

# Encryption functions for CEX credentials (Compact: AES-128-CTR)
encrypt_cex_credential <- function(plaintext) {
    if (is.null(plaintext) || plaintext == "") return(NULL)
    
    tryCatch({
        key_env <- Sys.getenv("CEX_ENCRYPTION_KEY")
        if (key_env == "") stop("CEX_ENCRYPTION_KEY not set")
        
        # AES-128 key (16 bytes)
        key <- openssl::sha256(charToRaw(key_env))[1:16]
        
        # 16-byte IV for AES
        iv <- openssl::rand_bytes(16)
        
        # Encrypt
        encrypted <- openssl::aes_ctr_encrypt(charToRaw(plaintext), key, iv)
        
        # Return as hex (compact)
        return(paste(c(rawToHex(iv), rawToHex(encrypted)), collapse = ""))
        
    }, error = function(e) {
        cat(sprintf("Encryption error: %s\n", e$message))
        return(NULL)
    })
}

decrypt_cex_credential <- function(encrypted_hex) {
    if (is.null(encrypted_hex) || encrypted_hex == "") return(NULL)
    
    tryCatch({
        key_env <- Sys.getenv("CEX_ENCRYPTION_KEY")
        if (key_env == "") stop("CEX_ENCRYPTION_KEY not set")
        
        # AES-128 key (16 bytes)
        key <- openssl::sha256(charToRaw(key_env))[1:16]
        
        # Extract IV (first 32 hex chars = 16 bytes) and encrypted data
        iv <- hex2raw(substr(encrypted_hex, 1, 32))
        encrypted <- hex2raw(substr(encrypted_hex, 33, nchar(encrypted_hex)))
        
        # Decrypt
        decrypted <- openssl::aes_ctr_decrypt(encrypted, key, iv)
        
        return(rawToChar(decrypted))
        
    }, error = function(e) {
        cat(sprintf("Decryption error: %s\n", e$message))
        return(NULL)
    })
}

# Get detailed CEX balance with all assets
get_cex_balance_details <- function(subaccount_id) {
    require(reticulate)
    
    tryCatch({
        # Get subaccount credentials
        result <- db_query(sprintf(
            "SELECT exchange, cex_api_key_encrypted, cex_secret_encrypted, cex_passphrase_encrypted
             FROM cex_subaccounts WHERE id = %d AND is_active = TRUE",
            subaccount_id
        ))
        
        if (nrow(result) == 0) return(list(assets = list(), total_usd = 0))
        
        # Decrypt credentials
        exchange <- result$exchange[1]
        api_key <- decrypt_cex_credential(result$cex_api_key_encrypted[1])
        secret <- decrypt_cex_credential(result$cex_secret_encrypted[1])
        passphrase <- if (!is.null(result$cex_passphrase_encrypted[1]) && result$cex_passphrase_encrypted[1] != "") {
            decrypt_cex_credential(result$cex_passphrase_encrypted[1])
        } else {
            NULL
        }
        
        # Initialize CCXT exchange
        ccxt <- import("ccxt")
        
        # Detect Cloud API Key
        is_cloud <- grepl("^organizations/.*/apiKeys/", api_key)
        exchange_name <- if (exchange == "coinbase") "coinbase" else exchange
        
        exchange_obj <- if (is_cloud && exchange == "coinbase") {
            ccxt[[exchange_name]](dict(
                apiKey = api_key,
                secret = secret
            ))
        } else {
            ccxt[[exchange_name]](dict(
                apiKey = api_key,
                secret = secret,
                password = passphrase
            ))
        }
        
        # Fetch balance
        balance <- exchange_obj$fetchBalance()
        
        # Stablecoins (assumed $1)
        stablecoins <- c("USD", "USDC", "USDT", "DAI", "BUSD", "FDUSD", "TUSD")
        
        # Extract assets with non-zero balances and calculate USD value
        assets <- list()
        total_usd <- 0
        
        for (currency in names(balance)) {
            if (currency %in% c("info", "free", "used", "total", "timestamp", "datetime")) next
            
            asset_data <- balance[[currency]]
            if (is.null(asset_data) || is.null(asset_data$total)) next
            
            total_amount <- suppressWarnings(as.numeric(asset_data$total))
            if (is.na(total_amount) || total_amount <= 0) next
            
            # Calculate USD value
            price <- 0
            if (currency %in% stablecoins) {
                # Stablecoins are $1
                usd_value <- total_amount
                price <- 1
            } else {
                # Fetch ticker price for other assets
                usd_value <- 0
                tryCatch({
                    ticker_symbol <- paste0(currency, "/USDT")
                    # Try USDT pair first
                    ticker <- exchange_obj$fetchTicker(ticker_symbol)
                    price <- suppressWarnings(as.numeric(ticker$last))
                    if (!is.na(price) && price > 0) {
                        usd_value <- total_amount * price
                    }
                }, error = function(e) {
                    # Try USD pair
                    tryCatch({
                        ticker_symbol <- paste0(currency, "/USD")
                        ticker <- exchange_obj$fetchTicker(ticker_symbol)
                        price <<- suppressWarnings(as.numeric(ticker$last))
                        if (!is.na(price) && price > 0) {
                            usd_value <<- total_amount * price
                        }
                    }, error = function(e2) {
                        # If no ticker available, mark as 0
                        cat(sprintf("  ⚠️ Could not fetch price for %s\n", currency))
                        price <<- 0
                        usd_value <<- 0
                    })
                })
            }
            
            assets[[length(assets) + 1]] <- list(
                currency = currency,
                free = suppressWarnings(as.numeric(asset_data$free)),
                used = suppressWarnings(as.numeric(asset_data$used)),
                total = total_amount,
                usd_value = usd_value,
                price = price
            )
            
            if (!is.na(usd_value) && usd_value > 0) {
                total_usd <- total_usd + usd_value
            }
        }
        
        # Update database with calculated total
        db_execute(sprintf(
            "UPDATE cex_subaccounts 
             SET total_balance_usd = %.2f, 
                 last_balance_check = NOW(), 
                 last_balance_update = NOW()
             WHERE id = %d",
            total_usd, subaccount_id
        ))
        
        return(list(assets = assets, total_usd = total_usd))
        
    }, error = function(e) {
        cat(sprintf("Error fetching CEX balance details: %s\n", e$message))
        return(list(assets = list(), total_usd = 0))
    })
}

# Helper to convert raw bytes to hex string
rawToHex <- function(raw_data) {
    paste(as.character(raw_data), collapse = "")
}

# Helper to convert hex string to raw bytes
hex2raw <- function(hex_string) {
    as.raw(strtoi(sapply(seq(1, nchar(hex_string), 2), 
                         function(i) substr(hex_string, i, i+1)), 
                  base = 16))
}


