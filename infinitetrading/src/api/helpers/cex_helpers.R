###############################
# CEX Helper Functions        #
###############################

# Constants
CEX_MIN_GAS_BALANCE_USD <- 10.00
CEX_GAS_CHECK_INTERVAL <- 3600  # 1 hour in seconds
CEX_LOW_GAS_WARNING_USD <- 25.00

# Database wrapper functions for CEX operations
db_query <- function(query) {
    pool <- db_con(use_pool = TRUE)
    result <- tryCatch({
        DBI::dbGetQuery(pool, query)
    }, error = function(e) {
        stop(paste("Query error:", e$message))
    })
    return(result)
}

db_execute <- function(query) {
    pool <- db_con(use_pool = TRUE)
    result <- tryCatch({
        DBI::dbExecute(pool, query)
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
        
        # 8-byte IV for CTR mode
        iv <- openssl::rand_bytes(8)
        
        # Encrypt
        encrypted <- openssl::aes_ctr_encrypt(charToRaw(plaintext), key, iv)
        
        # Return as hex (compact ~50 chars)
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
        
        # Extract IV (first 16 hex chars = 8 bytes) and encrypted data
        iv <- hex2raw(substr(encrypted_hex, 1, 16))
        encrypted <- hex2raw(substr(encrypted_hex, 17, nchar(encrypted_hex)))
        
        # Decrypt
        decrypted <- openssl::aes_ctr_decrypt(encrypted, key, iv)
        
        return(rawToChar(decrypted))
        
    }, error = function(e) {
        cat(sprintf("Decryption error: %s\n", e$message))
        return(NULL)
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

