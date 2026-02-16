#Loading dependencies
# Auto-install required packages if not available
required_packages = c("httr", "jsonlite", "lubridate", "TTR", "quantmod", "DBI", "RMariaDB", "dotenv")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(paste0("Installing ", pkg, "...\n"))
    install.packages(pkg, repos="http://cran.rstudio.com/", quiet=TRUE)
  }
}

require(jsonlite); require(lubridate); require(TTR); require(quantmod)
require(DBI); require(RMariaDB); require(dotenv); require(httr)

#Loading environmental variables
# Dynamic .env loading - works in both local and EC2 environments
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    script_dir = dirname(normalizePath(ofile))
  } else {
    script_dir = normalizePath(".")
  }
  # Navigate up from strategies/ to repo root
  wd = paste0(dirname(script_dir), "/")
}

# Try multiple possible .env locations
env_path = paste0(wd, ".env")
if (!file.exists(env_path)) {
  env_path = "~/.env"
}
if (file.exists(env_path)) {
  load_dot_env(env_path)
} else {
  warning(paste0("No .env file found at ", env_path, ". Ensure environment variables are set."))
}

#Setting credentials
db_user = Sys.getenv("db_user")
db_password = Sys.getenv("db_password")
db_schema = "infinitetrading"
apiKey = Sys.getenv("ITP_APIKEY")

#Database connection
db_connect = function(user,hostname,port,password,dbname,rmysql=FALSE) {
        default_authentication_plugin=password
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname,hostname = hostname)
        return(con)
}
db_con = function(db=db_schema) {
        db_host_env = Sys.getenv("db_ip")
        if (db_host_env == "") db_host_env = Sys.getenv("db_host")
        if (db_host_env == "") db_host_env = "3.135.99.211"
        db_credentials = c(); db_credentials$user = db_user; db_credentials$ip = db_host_env; db_credentials$password = db_password; db_credentials$port = 3306
        con = db_connect(db_credentials$user,db_credentials$ip,db_credentials$port,db_credentials$password,dbname=db)
        return(con)
}
push_message <- function(platform, channel, message) {
  con <- db_con()
  if (nchar(message)[1] > 255) {
        print(paste0("Message is being cut because its too long: ",message))
        message = substr(message, 1, 255)
  }
  Sys.sleep(1)
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%OS9")
  #timestamp <- strftime(Sys.time(), "%Y-%m-%d %H:%M:%OS3")
  insert_query <- sprintf("INSERT IGNORE INTO messages (timestamp, platform, channel, message) VALUES ('%s','%s', '%s', '%s')",timestamp, platform, channel, message)
  print(paste0("inserting query into the db: :",insert_query))
  dbExecute(con, insert_query,append=TRUE)
}
discord = function(msg,channel="#dhedge-pools",db=TRUE) {
        if (db) {
                result = tryCatch({push_message(platform="discord",channel=channel,message=msg); Sys.sleep(0.0001)}, error = function(e) {
                print(paste0("An error ocurred:, e$message"))})
        }
        else { discord_NODB(msg=msg,channel=channel) }
}

#API Adapter

itp_api <- function(endpoint, params) {
  url <- paste0("https://api.infinitetrading.io/", endpoint)
  
  # For setBot: send query params, no body
  if (endpoint == "setBot") {
    response <- POST(url, query = params, body = "", encode = "raw")
  } else {
    response <- GET(url, query = params)
  }
  
  content_text <- content(response, "text", encoding = "UTF-8")
  cat("Response from API:", content_text, "\n")
}


# Mapping timeframes to their equivalent durations in seconds
timeframe_to_seconds <- list(
  '1m' = 60,
  '5m' = 300,
  '15m' = 900,
  '1h' = 3600,
  '6h' = 21600,
  '1d' = 86400,
  '1w' = 604800
)

get_candles_from_coingecko = function(id,days=30,currency="usd") { 
	url <- paste0("https://api.coingecko.com/api/v3/coins/",id,"/ohlc")
	queryString <- list(vs_currency = currency,days = days)
	response <- VERB("GET", url, query = queryString, add_headers('x-cg-demo-api-key' = 'CG-zpaFwSa3VyCHDWxGV9L1T6gt'), content_type("application/octet-stream"), accept("application/json"))
	data =jsonlite::fromJSON(content(response,"text"))
	colnames(data) = c("Time","Open","High","Low","Close")
	return(data)
}
get_candles_from_mysql <- function(pair, timeframe) {
  con <- db_con()
  table_name <- paste0("`coinbase_", pair, "_", timeframe, "`")
  # Force numeric ordering even if 'time' is stored as text
  query <- paste0(
    "SELECT * FROM ", table_name,
    " WHERE `time` IS NOT NULL",
    " ORDER BY CAST(`time` AS UNSIGNED) ASC"
  )

  raw <- tryCatch({
    dbGetQuery(con, query)
  }, error = function(e) {
    message(sprintf("error fetching candles: %s", e$message)); NULL
  })
  if (is.null(raw) || nrow(raw) == 0) return(raw)

  # If time is in milliseconds, divide by 1000. If it's already seconds, remove the /1000.
  t_numeric <- as.numeric(raw[['time']])
  t_posix   <- as.POSIXct(t_numeric/1000, origin = "1970-01-01", tz = "UTC")

  OHLC <- data.frame(
    time   = t_posix,
    low    = as.numeric(raw[['low']]),
    high   = as.numeric(raw[['high']]),
    open   = as.numeric(raw[['open']]),
    close  = as.numeric(raw[['close']]),
    volume = as.numeric(raw[['volume']]),
    row.names = NULL
  )

  # Final safety: ensure sorted in R as well
  OHLC <- OHLC[order(OHLC$time), ]
  rownames(OHLC) <- NULL
  OHLC
}
get_candles_with_retry <- function(pair, numcandles, timeframe, retries = 3, delay = 1) { 
  attempt <- 0 
  while (attempt < retries) { 
    tryCatch({ 
      #candles <- get_candles(pair, numcandles, timeframe) 
      candles <- get_candles_from_mysql(pair,timeframe) 
      if (!is.null(candles)) { 
        return(candles) 
      } 
    }, error = function(e) { 
      cat(sprintf("Error fetching candles: %s\n", e$message)) 
      if (grepl("ban", tolower(e$message)) || grepl("403", e$message) || grepl("rate limit", tolower(e$message))) { 
        cat("It looks like your IP might be banned or rate-limited.\n") 
        break 
      } 
    }) 
    attempt <- attempt + 1 
    cat(sprintf("Retrying... (%d/%d)\n", attempt, retries)) 
    Sys.sleep(delay) 
  } 
  return(NULL) 
}

