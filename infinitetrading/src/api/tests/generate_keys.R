if (!require(openssl)) {
    install.packages("openssl")
    library(openssl)
}
# Generate a 256-bit (32 bytes) random key
key_raw <- rand_bytes(32)  # This uses openssl to generate cryptographically secure bytes

# Convert the raw bytes to a hexadecimal string for easy storage
#key_hex <- bin2hex(key_raw)

key_base64 <- base64_encode(key_raw)

# Print the key
print(key_base64)

