options(warn = -1)  # Suppress warnings
invisible(suppressMessages(library(openssl)))
invisible(suppressMessages(library(dotenv)))
load_dot_env("/home/ubuntu/infinitetrading/src/api/.env")

decode_base64 <- function(base64_string) openssl::base64_decode(base64_string)

hex_to_raw <- function(hex_string) {
    Encoding(hex_string) <- "ASCII"
    hex_string <- gsub("[^0-9a-fA-F]", "", hex_string)
    raw_vector <- sapply(seq(1, nchar(hex_string, type = "bytes"), by = 2), function(i) {
        as.raw(strtoi(substr(hex_string, i, i + 1), base = 16))
    })
    raw_vector
}

raw_to_hex <- function(raw) paste0(sprintf("%02x", as.integer(raw)), collapse = "")
raw_to_char <- function(raw) rawToChar(raw)

secure_encrypt <- function(data, hexmode = FALSE) {
    encryption_key <- decode_base64(Sys.getenv("encryption_key"))
    iv <- rand_bytes(16) 
    if (hexmode) data <- hex_to_raw(data)
    else data <- charToRaw(data)
    encrypted_data <- openssl::aes_cbc_encrypt(data, key = encryption_key, iv = iv)
    encrypted_iv_and_data <- c(iv, encrypted_data)  # Prepend IV to encrypted data
    encrypted = raw_to_hex(encrypted_iv_and_data)
    url_safe <- gsub("\\+", "-", gsub("/", "_", gsub("=+$", "", encrypted)))
    return(url_safe)
}

secure_decrypt <- function(data) {
    encryption_key <- decode_base64(Sys.getenv("encryption_key"))
    data_raw = gsub("-", "+", gsub("_", "/", data))  # Reverse URL-safe changes
    data_raw <- hex_to_raw(data)
    iv <- data_raw[1:16]
    data_encrypted <- data_raw[-(1:16)]

    decrypted_data <- openssl::aes_cbc_decrypt(data_encrypted, key = encryption_key, iv = iv)
    decrypted = raw_to_hex(decrypted_data)
    return(raw_to_hex(decrypted_data))
}

remove_0x_prefix <- function(private_key) {
    if (startsWith(private_key, "0x")) return(substring(private_key, 3))
    return(private_key)
}

add_0x_prefix <- function(private_key) {
    if (!startsWith(private_key, "0x")) return(paste0("0x", private_key))
    return(private_key)
}

decrypt_twice <- function(data) {
    first_decryption <- secure_decrypt(data)
    print(paste("First decryption output:", first_decryption))
    second_decryption <- secure_decrypt(first_decryption)
    return(second_decryption)
}

args <- commandArgs(trailingOnly = TRUE)

if (length(args) >=1) { api_key <- args[1]; private_key <- secure_decrypt(api_key); cat(private_key) }

#private_key <- remove_0x_prefix("0xfcfa4c7906d174e6dffcdbe69f1d43446474b6c050f456674fe8570bc23ef288")
#encrypted_private_key <- secure_encrypt(private_key, hexmode = TRUE)
#decrypted_private_key <- add_0x_prefix(secure_decrypt(encrypted_private_key))
#encrypted_api_key <- secure_encrypt(encrypted_private_key,hexmode=TRUE) 

# Print results
#print(paste("Private key:", add_0x_prefix(private_key)))
#print(paste("Encrypted private key (API KEY): ", encrypted_private_key))
#print(paste("Decrypted private key:", decrypted_private_key))
#print(paste("Encrypted API key:", encrypted_api_key))
#pk <- add_0x_prefix(decrypt_twice(encrypted_api_key))
#print(paste0("Private key from Encrypted API key: ", pk))
