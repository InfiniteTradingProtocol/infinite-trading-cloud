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
        cat(sprintf("\n=== Fetching CEX balance for subaccount ID: %d ===\n", subaccount_id))
        
        # Get subaccount credentials
        result <- db_query(sprintf(
            "SELECT exchange, cex_api_key_encrypted, cex_secret_encrypted, cex_passphrase_encrypted
             FROM cex_subaccounts WHERE id = %d AND is_active = TRUE",
            subaccount_id
        ))
        
        if (nrow(result) == 0) {
            cat("No active subaccount found\n")
            return(list(assets = list(), total_usd = 0))
        }
        
        # Decrypt credentials
        exchange <- result$exchange[1]
        cat(sprintf("Exchange: %s\n", exchange))
        
        api_key <- decrypt_cex_credential(result$cex_api_key_encrypted[1])
        secret <- decrypt_cex_credential(result$cex_secret_encrypted[1])
        
        has_passphrase <- !is.null(result$cex_passphrase_encrypted[1]) && 
                         !is.na(result$cex_passphrase_encrypted[1]) && 
                         nchar(result$cex_passphrase_encrypted[1]) > 0
        
        passphrase <- if (isTRUE(has_passphrase)) {
            decrypt_cex_credential(result$cex_passphrase_encrypted[1])
        } else {
            NULL
        }
        
        # Initialize CCXT exchange
        ccxt <- import("ccxt")
        
        # Detect Cloud API Key
        is_cloud <- grepl("^organizations/.*/apiKeys/", api_key)
        exchange_name <- if (exchange == "coinbase") "coinbase" else exchange
        
        exchange_obj <- if (isTRUE(is_cloud) && exchange == "coinbase") {
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
        cat("Fetching balance from exchange...\n")
        balance <- tryCatch({
            # For Coinbase Cloud API, bypass CCXT and use Advanced Trade SDK directly via Python helper
            if (isTRUE(is_cloud) && exchange == "coinbase") {
                cat("🔄 Using Coinbase Advanced Trade SDK (bypassing CCXT)...\n")
                
                # Call Python helper script that uses coinbase-advanced-py SDK
                python_script <- "/home/ubuntu/coinbase_cloud_balance.py"
                
                if (!file.exists(python_script)) {
                    cat("❌ Python helper script not found, falling back to CCXT...\n")
                    # Fall back to CCXT attempt
                    bal <- exchange_obj$fetchBalance()
                    return(bal)
                }
                
                # Escape quotes in secret key for shell command
                # Write credentials to temporary files to avoid shell escaping issues
                tmp_key_file <- tempfile()
                tmp_secret_file <- tempfile()
                writeLines(api_key, tmp_key_file)
                writeLines(secret, tmp_secret_file)
                
                cmd <- sprintf("python3 '%s' \"$(cat '%s')\" \"$(cat '%s')\" 2>&1", 
                              python_script, tmp_key_file, tmp_secret_file)
                
                cat(sprintf("Executing Python helper...\n"))
                result_json <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
                
                # Clean up temp files
                unlink(tmp_key_file)
                unlink(tmp_secret_file)
                
                if (length(result_json) == 0) {
                    cat("❌ Python helper returned empty response\n")
                    return(list(total = list(), free = list(), used = list()))
                }
                
                # Debug: print what we got
                cat(sprintf("Python response length: %d lines\n", length(result_json)))
                if (length(result_json) > 0) {
                    cat("Python output:\n")
                    for (line in result_json) {
                        cat(sprintf("  %s\n", line))
                    }
                }
                
                result <- fromJSON(paste(result_json, collapse = "\n"))
                
                if (isTRUE(result$success)) {
                    cat(sprintf("✅ Found %d assets with total value: $%.2f\n", result$count, result$total_usd))
                    
                    # Convert to CCXT-like balance structure
                    total_bal <- list()
                    free_bal <- list()
                    used_bal <- list()
                    
                    if (!is.null(result$assets) && length(result$assets) > 0) {
                        for (asset in result$assets) {
                            currency <- asset$currency
                            total_bal[[currency]] <- asset$total
                            free_bal[[currency]] <- asset$available
                            used_bal[[currency]] <- asset$hold
                            
                            cat(sprintf("  → %s: %.8f (available: %.8f, price: $%.4f, value: $%.2f)\n",
                                currency, asset$total, asset$available, asset$price_usd, asset$value_usd))
                        }
                    }
                    
                    list(
                        total = total_bal,
                        free = free_bal,
                        used = used_bal
                    )
                } else {
                    cat(sprintf("❌ Python helper failed: %s\n", result$error))
                    return(list(total = list(), free = list(), used = list()))
                }
            } else {
                # For non-Cloud API exchanges, use standard fetchBalance()
                bal <- exchange_obj$fetchBalance()
                cat("✅ fetchBalance() successful\n")
                bal
            }
        }, error = function(e) {
            cat(sprintf("❌ Error calling fetch method: %s\n", e$message))
            
            # Return empty balance structure to allow endpoint to continue
            return(list(
                total = list(),
                free = list(),
                used = list()
            ))
        })
        
        # Debug: print balance structure
        cat("Balance structure received:\n")
        cat(sprintf("Balance class: %s\n", class(balance)))
        
        tryCatch({
            balance_names <- names(balance)
            cat(sprintf("Balance names: %s\n", paste(balance_names, collapse=", ")))
        }, error = function(e) {
            cat(sprintf("Error getting balance names: %s\n", e$message))
        })
        
        # Stablecoins (assumed $1)
        stablecoins <- c("USD", "USDC", "USDT", "DAI", "BUSD", "FDUSD", "TUSD")
        
        # Extract assets with non-zero balances and calculate USD value
        assets <- list()
        total_usd <- 0
        
        # CCXT balance structure has nested structure - access properly
        # The actual asset balances are in balance$total, balance$free, etc. which are named vectors/lists
        # Or we need to iterate through the Python dict properly
        tryCatch({
            # Get the 'total' balances dict from CCXT
            if (!is.null(balance$total)) {
                # Convert Python dict to R list if needed
                total_balances <- if (inherits(balance$total, "python.builtin.dict")) {
                    reticulate::py_to_r(balance$total)
                } else {
                    balance$total
                }
                
                currency_keys <- names(total_balances)
                cat(sprintf("Found %d currencies with balances\n", length(currency_keys)))
            } else {
                currency_keys <- character(0)
                cat("Warning: balance$total is NULL\n")
            }
        }, error = function(e) {
            cat(sprintf("Error extracting currency keys: %s\n", e$message))
            currency_keys <<- character(0)
        })
        
        for (currency in currency_keys) {
            asset_data <- tryCatch({
                list(
                    total = if(!is.null(balance$total)) balance$total[[currency]] else 0,
                    free = if(!is.null(balance$free)) balance$free[[currency]] else 0,
                    used = if(!is.null(balance$used)) balance$used[[currency]] else 0
                )
            }, error = function(e) {
                cat(sprintf("Error accessing %s: %s\n", currency, e$message))
                NULL
            })
            
            if (is.null(asset_data)) next
            if (is.null(asset_data$total)) next
            
            total_amount <- suppressWarnings(as.numeric(asset_data$total))
            if (is.na(total_amount) || total_amount <= 0) next
            
            cat(sprintf("Processing %s: %.8f\n", currency, total_amount))
            
            # Calculate USD value
            price <- 0
            usd_value <- 0
            
            if (currency %in% stablecoins) {
                # Stablecoins are $1
                usd_value <- total_amount
                price <- 1
                cat(sprintf("  → Stablecoin: $%.2f\n", usd_value))
            } else {
                # Fetch ticker price for other assets
                price_found <- FALSE
                
                # Try USDT pair first
                tryCatch({
                    ticker_symbol <- paste0(currency, "/USDT")
                    ticker <- exchange_obj$fetchTicker(ticker_symbol)
                    
                    if (!is.null(ticker$last)) {
                        price <- suppressWarnings(as.numeric(ticker$last))
                        if (!is.na(price) && price > 0) {
                            usd_value <- total_amount * price
                            price_found <- TRUE
                            cat(sprintf("  → %s price: $%.4f, value: $%.2f\n", ticker_symbol, price, usd_value))
                        }
                    }
                }, error = function(e) {
                    # Try USD pair
                    tryCatch({
                        ticker_symbol <- paste0(currency, "/USD")
                        ticker <- exchange_obj$fetchTicker(ticker_symbol)
                        
                        if (!is.null(ticker$last)) {
                            price <<- suppressWarnings(as.numeric(ticker$last))
                            if (!is.na(price) && price > 0) {
                                usd_value <<- total_amount * price
                                price_found <<- TRUE
                                cat(sprintf("  → %s price: $%.4f, value: $%.2f\n", ticker_symbol, price, usd_value))
                            }
                        }
                    }, error = function(e2) {
                        cat(sprintf("  ⚠️ Could not fetch price for %s\n", currency))
                    })
                })
                
                if (!isTRUE(price_found)) {
                    price <- 0
                    usd_value <- 0
                }
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
        
        cat(sprintf("=== Total USD: $%.2f ===\n\n", total_usd))
        
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
        cat(sprintf("Error traceback: %s\n", paste(capture.output(traceback()), collapse = "\n")))
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


