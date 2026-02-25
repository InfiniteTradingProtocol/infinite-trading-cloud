########################
# Infinite Trading API
# Author: etherpilled
########################

#* @apiTitle Infinite Trading Protocol API v1
# Packages required
####################

# Main packages
require(plumber); require(data.table); require(DBI); require(lubridate); require(jsonlite); require(httr);

# require(RSQLite); require(redoc)

# Parallel processing
require(future); require(promises); plan(multicore); options(future.multicore.workers = parallel::detectCores())


####################
# Dependencies
####################

wd = "~/infinitetrading/src/"
source(paste0(wd,"/api/helpers/apiHelpers.R"))
source(paste0(wd,"/api/messaging.R"))
source(paste0(wd,"/api/reporting.R"))   # <- contains send_request_report
source(paste0(wd,"/tradebot/defi.R"))
source(paste0(wd,"/api/helpers/endpoints.R"))

add_endpoint = function(name,pr = NULL) {
  path = paste0(wd,"api/gateway/endpoints/")
  file = paste0(path,name,".R")
  print(paste0("mounting :",file))
  if (file.exists(file)) { source(file) }
  else { print(paste0("** ERROR **: file: ",file," doesnt exist, skipping")) }
}

#####################################################################################
# Run the API
#####################################################################################

pr <- Plumber$new()
options(encoding = "UTF-8")

# CHANGE 1: request_tracker must be an environment (not a list) for exists(..., envir=...) to work
request_tracker <- new.env(parent = emptyenv())
assign("request_tracker", request_tracker, envir = .GlobalEnv)

limit_store <- new.env(parent = emptyenv())

rate_limit_middleware <- function(req) {
  # Identify the client (simplistic approach using IP address)
  client_ip <- req$HTTP_X_REAL_IP
  # Set limits: max requests allowed and time window in seconds
  max_requests <- 600  # Max requests allowed in the time window
  time_window <- 60    # Time window in seconds

  # Get the current time
  current_time <- Sys.time()

  # Initialize the request tracker for the client if it doesn't exist
  if (length(client_ip) > 0)  {
    if (!exists(client_ip, request_tracker, inherits = FALSE)) request_tracker[[client_ip]] <- c()  # Init
    # Check if client_ip already has request data
    if (!is.null(request_tracker[[client_ip]])) {
      # Keep only the requests within the time window
      valid_requests <- request_tracker[[client_ip]] > (current_time - time_window)
      if (any(valid_requests)) {
        request_tracker[[client_ip]] <- request_tracker[[client_ip]][valid_requests]
      } else {
        request_tracker[[client_ip]] <- c()  # Reset if no valid requests
      }
    } else {
      request_tracker[[client_ip]] <- c()    # Initialize if no previous requests
    }

    # Add the current request timestamp to the tracker
    request_tracker[[client_ip]] <- c(request_tracker[[client_ip]], current_time)

    # Check if the request limit has been exceeded
    if (length(request_tracker[[client_ip]]) > max_requests) {
      res = list()  # Initialize the response as a list
      res$status <- 429  # Set status code directly on the res object
      res$body <- toJSON(list(error = "Rate limit exceeded"), auto_unbox = TRUE)

      # report the rate-limit event
      try(send_request_report(req, status = 429, note = "Rate limit exceeded", report = "GATEWAY"), silent = TRUE)

      return(res)
    }
  } else { client_ip = "0.0.0.0" }

  # Log request if endpoint exists
  clean_endpoint = sub("^/", "", req$PATH_INFO)
  endpoint_exists <- any(clean_endpoint == endpoints)

  if (isTRUE(endpoint_exists) || clean_endpoint == "aaveV3") send_request_report(req, status = NA_integer_, note = "Inbound Request", report = "GATEWAY")

  plumber::forward()  # Forward the request to the next handler
}

# Register the middleware
pr$registerHooks(list("preroute" = rate_limit_middleware))
pr$registerHooks(list(
  "postroute" = function(req, res, value) {
    status <- tryCatch({ if (!is.null(res$status)) as.integer(res$status) else 200L }, error = function(e) NA_integer_)
    clean_endpoint = sub("^/", "", req$PATH_INFO)  
    endpoint_exists <- any(clean_endpoint == endpoints)
    if (isTRUE(endpoint_exists) || clean_endpoint == "aaveV3") {
	    note <- summarize_value(value)
	    try(send_request_report(req, status = status, note = paste0(" Server Response: ","\n",note), report = "GATEWAY"), silent = TRUE)
    }
    return(value) # MUST return unchanged
  }
))

# Load and mount each endpoint
for (endpoint in endpoints) {
  add_endpoint(endpoint, pr)
}

pr$setDocs("swagger")

# Set API specification for Swagger documentation
pr$setApiSpec(function(spec) {
  spec$info$title <- "Infinite Trading API"
  spec$info$description <- "Deploy automated trading strategies in DeFi without managing Web3 infrastructure. To maintain stability and ensure a seamless user experience, some basic endpoints have been temporarily closed. Visit https://www.infinitetrading.io/managers and sign in with your wallet to create new gas wallets, generate API keys, and link vaults to those wallets for API-based vault management. The front-end abstracts these processes to make interaction simple for all users."
  spec$info$version <- "1.0.0"
  for (path in hidden_endpoints) {
    spec$paths[[path]] <- NULL
  }
  return(spec)
})
pr$run(host="0.0.0.0", port=8003)

