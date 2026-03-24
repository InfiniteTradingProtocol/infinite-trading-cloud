###############################
# CEX Compact Encryption      #
# - Hex-encoded AES-128       #
# - Credentials in RDS        #
###############################

require(openssl)

# Compact encrypt (hex output, ~50 chars instead of base64 ~80 chars)
encrypt_cex_credential <- function(plaintext) {
    if (is.null(plaintext) || plaintext == "") return(NULL)
    
    tryCatch({
        key_env <- Sys.getenv("CEX_ENCRYPTION_KEY")
        if (key_env == "") stop("CEX_ENCRYPTION_KEY not set")
        
        # AES-128 key (16 bytes)
        key <- sha256(charToRaw(key_env))[1:16]
        
        # 8-byte IV for CTR mode
        iv <- openssl::rand_bytes(8)
        
        # Encrypt
        encrypted <- openssl::aes_ctr_encrypt(charToRaw(plaintext), key, iv)
        
        # Return as hex (compact)
        return(paste(c(rawToHex(iv), rawToHex(encrypted)), collapse = ""))
        
    }, error = function(e) {
        cat(sprintf("Encryption error: %s\n", e$message))
        return(NULL)
    })
}

# Decrypt hex-encoded credential
decrypt_cex_credential <- function(encrypted_hex) {
    if (is.null(encrypted_hex) || encrypted_hex == "") return(NULL)
    
    tryCatch({
        key_env <- Sys.getenv("CEX_ENCRYPTION_KEY")
        if (key_env == "") stop("CEX_ENCRYPTION_KEY not set")
        
        # AES-128 key (16 bytes)
        key <- sha256(charToRaw(key_env))[1:16]
        
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

# Test encryption
test_cex_encryption <- function() {
    cat("Testing CEX compact encryption...\n")
    
    test_api_key <- "test_key_12345"
    test_secret <- "test_secret_abcdef"
    
    # Encrypt
    enc_key <- encrypt_cex_credential(test_api_key)
    enc_secret <- encrypt_cex_credential(test_secret)
    
    cat(sprintf("API Key encrypted (%d chars): %s\n", nchar(enc_key), enc_key))
    cat(sprintf("Secret encrypted (%d chars): %s\n", nchar(enc_secret), enc_secret))
    
    # Decrypt
    dec_key <- decrypt_cex_credential(enc_key)
    dec_secret <- decrypt_cex_credential(enc_secret)
    
    cat(sprintf("API Key match: %s\n", dec_key == test_api_key))
    cat(sprintf("Secret match: %s\n", dec_secret == test_secret))
    
    cat("\n✅ Encryption test complete!\n")
}

# Helper to convert raw to hex
rawToHex <- function(raw_bytes) {
    paste(sprintf("%02x", as.integer(raw_bytes)), collapse = "")
}

# Helper to convert hex to raw
hex2raw <- function(hex_string) {
    as.raw(strtoi(substring(hex_string, seq(1, nchar(hex_string), 2), seq(2, nchar(hex_string), 2)), 16))
}
