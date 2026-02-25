library(redux)

# Connect to Redis server
r <- redux::hiredis()

# Fetch the values from Redis
eth_price <- r$GET("ETH-USD")
matic_price <- r$GET("MATIC-USD")

# Check the type of the fetched data
print(class(eth_price))
print(class(matic_price))

# Convert to character if necessary
if (is.raw(eth_price)) {
  eth_price <- rawToChar(eth_price)
}
if (is.raw(matic_price)) {
  matic_price <- rawToChar(matic_price)
}

# Print the values
print(eth_price)
print(matic_price)

