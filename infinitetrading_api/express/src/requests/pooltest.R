# Load the httr package for making HTTP requests
library(httr)


# Define the URL with the endpoint and query parameter
url <- "http://localhost:8000/repay?platform=aave&asset=0x3c499c542cef5e3811e1192ce70d8cc03d5c3359&share=10&pool=0xb48a390270d41a1663a68708210b7ef4d89ba9f6&network=polygon&apiKey=b990f2d0e41e6b636cfa66917d59d2ce414015383968c9e9247e9873b94f7e4327dac89bba564487de4d0da4d5b2309df2f859b1df241b5c68f43865859038ae"

# Send the GET request to the server
response <- GET(url)

# Check the status code of the response
if (status_code(response) == 200) {
  # If the request was successful, print the content of the response
  content <- content(response, "text")
  print(content)
} else {
  # If the request failed, print the status code
  print(paste("Failed to fetch data. Status code:", status_code(response)," Response: ", response))
}

#return(0)


# Define the URL with the endpoint and query parameter
url <- "http://localhost:8000/getWallet?apiKey=79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688"

# Send the GET request to the server
response <- GET(url)

# Check the status code of the response
if (status_code(response) == 200) {
  # If the request was successful, print the content of the response
  content <- content(response, "text")
  print(content)
} else {
  # If the request failed, print the status code
  print(paste("Failed to fetch data. Status code:", status_code(response)," Response: ", response))
}

return(0) 

# Define the URL with the endpoint and query parameter
url <- "http://localhost:8000/getManagerFee?pool=0xb48a390270d41a1663a68708210b7ef4d89ba9f6&network=polygon&apiKey=b990f2d0e41e6b636cfa66917d59d2ce414015383968c9e9247e9873b94f7e4327dac89bba564487de4d0da4d5b2309df2f859b1df241b5c68f43865859038ae"

# Send the GET request to the server
response <- GET(url)

# Check the status code of the response
if (status_code(response) == 200) {
  # If the request was successful, print the content of the response
  content <- content(response, "text")
  print(content)
} else {
  # If the request failed, print the status code
  print(paste("Failed to fetch data. Status code:", status_code(response)," Response: ", response))
}

return(0)
# Define the URL with the endpoint and query parameter
url <- "http://localhost:8000/mintManagerFee?pool=0xd28073e24a2e1dfae3ea48a66a6c1003e2836241&network=polygon&apiKey=b391d7ac409c0f6f441aaf4777065228982f906bc2c090303c7bb7dbcd76aeb8e8c088d083ae6920f311f7a52e03e1ae934f5394d999c810b3c0b8ab3aafe4f7"

# Send the GET request to the server
response <- GET(url)

# Check the status code of the response
if (status_code(response) == 200) {
  # If the request was successful, print the content of the response
  content <- content(response, "text")
  print(content)
} else {
  # If the request failed, print the status code
  print(paste("Failed to fetch data. Status code:", status_code(response)," Response: ", response))
}
