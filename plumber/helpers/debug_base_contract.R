library(httr)
library(jsonlite)

# Base RPC
rpc_url <- "https://base.llamarpc.com"
vault <- "0xd92989c7e93a46fc10e6f49b796b529e2b076e3d"

# Helper function for eth_call
ethCall <- function(to, data, rpc_url) {
  body <- list(
    jsonrpc = "2.0",
    method = "eth_call",
    params = list(list(to = to, data = data), "latest"),
    id = 1
  )
  response <- POST(
    url = rpc_url,
    body = toJSON(body, auto_unbox = TRUE),
    add_headers("Content-Type" = "application/json")
  )
  result <- content(response, as = "parsed", type = "application/json")
  return(result)
}

# Helper to get contract code
getCode <- function(address, rpc_url) {
  body <- list(
    jsonrpc = "2.0",
    method = "eth_getCode",
    params = list(address, "latest"),
    id = 1
  )
  response <- POST(
    url = rpc_url,
    body = toJSON(body, auto_unbox = TRUE),
    add_headers("Content-Type" = "application/json")
  )
  result <- content(response, as = "parsed", type = "application/json")
  return(result)
}

cat("\n============================================================\n")
cat("DEBUGGING BASE CONTRACT\n")
cat("============================================================\n\n")

# Step 1: Check if contract exists
cat("Step 1: Checking if contract exists at", vault, "...\n")
code_result <- getCode(vault, rpc_url)
if ("result" %in% names(code_result) && nchar(code_result$result) > 2) {
  cat("✓ Contract exists! Code length:", nchar(code_result$result), "characters\n\n")
} else {
  cat("✗ No contract found at this address!\n")
  stop("Contract does not exist")
}

# Step 2: Try common dHEDGE functions
cat("Step 2: Testing various function calls...\n\n")

# Try tokenPrice() - 0x7ff36ab5
cat("Trying tokenPrice() [0x7ff36ab5]...\n")
result <- ethCall(vault, "0x7ff36ab5", rpc_url)
if ("result" %in% names(result) && !is.null(result$result)) {
  cat("✓ tokenPrice() works! Result:", result$result, "\n\n")
} else {
  cat("✗ tokenPrice() failed:", if("error" %in% names(result)) result$error$message else "unknown error", "\n\n")
}

# Try poolManagerLogic() - 0x3b1f8c9d
cat("Trying poolManagerLogic() [0x3b1f8c9d]...\n")
result <- ethCall(vault, "0x3b1f8c9d", rpc_url)
if ("result" %in% names(result) && !is.null(result$result)) {
  cat("✓ poolManagerLogic() works! Result:", result$result, "\n\n")
} else {
  cat("✗ poolManagerLogic() failed:", if("error" %in% names(result)) result$error$message else "unknown error", "\n\n")
}

# Try managerLogic() - 0xe0f9d3d7
cat("Trying managerLogic() [0xe0f9d3d7]...\n")
result <- ethCall(vault, "0xe0f9d3d7", rpc_url)
if ("result" %in% names(result) && !is.null(result$result)) {
  cat("✓ managerLogic() works! Result:", result$result, "\n\n")
} else {
  cat("✗ managerLogic() failed:", if("error" %in% names(result)) result$error$message else "unknown error", "\n\n")
}

# Try manager() - 0x481c6a75
cat("Trying manager() [0x481c6a75]...\n")
result <- ethCall(vault, "0x481c6a75", rpc_url)
if ("result" %in% names(result) && !is.null(result$result)) {
  cat("✓ manager() works! Result:", result$result, "\n\n")
} else {
  cat("✗ manager() failed:", if("error" %in% names(result)) result$error$message else "unknown error", "\n\n")
}

# Try factory() - 0xc45a0155
cat("Trying factory() [0xc45a0155]...\n")
result <- ethCall(vault, "0xc45a0155", rpc_url)
if ("result" %in% names(result) && !is.null(result$result)) {
  cat("✓ factory() works! Result:", result$result, "\n\n")
} else {
  cat("✗ factory() failed:", if("error" %in% names(result)) result$error$message else "unknown error", "\n\n")
}

cat("============================================================\n")
cat("Debug complete. Check which functions work above.\n")
cat("============================================================\n")

