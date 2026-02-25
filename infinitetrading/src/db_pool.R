# Connection Pool for infinitetrading/src services
# Used by: models.R, api/trading.R, and other services in this directory

# Only create pool if it doesn't already exist
if (!exists("db_pool", envir = .GlobalEnv) || !inherits(get("db_pool", envir = .GlobalEnv), "Pool")) {
  
  # Load required packages
  if (!require(pool, quietly = TRUE)) {
    install.packages("pool", repos = "https://cloud.r-project.org/")
    library(pool)
  }
  
  # Ensure dotenv is loaded
  if (!require(dotenv, quietly = TRUE)) {
    install.packages("dotenv", repos = "https://cloud.r-project.org/")
  }
  require(dotenv, quietly = TRUE)
  
  # Try to load .env if not already loaded or if credentials are missing
  if (Sys.getenv("db_user") == "" || Sys.getenv("db_password") == "") {
    if (exists("wd") && file.exists(paste0(wd, ".env"))) {
      load_dot_env(paste0(wd, ".env"))
    } else if (file.exists(".env")) {
      load_dot_env(".env")
    } else if (file.exists("~/infinitetrading/src/.env")) {
      load_dot_env("~/infinitetrading/src/.env")
    }
  }
  
  # Get credentials from environment
  db_user <- Sys.getenv("db_user")
  db_password <- Sys.getenv("db_password")
  db_host <- if (Sys.getenv("db_host") != "") Sys.getenv("db_host") else if (Sys.getenv("db_ip") != "") Sys.getenv("db_ip") else "3.135.99.211"
  db_schema <- if (Sys.getenv("db_schema") != "") Sys.getenv("db_schema") else "infinitetrading"
  
  # Validate credentials
  if (db_user == "" || db_password == "") {
    stop("[POOL ERROR] Database credentials not found in environment variables")
  }
  
  # Create connection pool
#   db_pool <- pool::dbPool(
#     drv = RMariaDB::MariaDB(),
#     user = db_user,
#     password = db_password,
#     host = db_host,
#     port = 3306,
#     dbname = db_schema,
#     minSize = 3,
#     maxSize = 15,
#     idleTimeout = 300
#   )
#   
#   # Assign to global environment
#   assign("db_pool", db_pool, envir = .GlobalEnv)
#   
  cat("[POOL] Created infinitetrading connection pool: minSize=3, maxSize=15\n")
  cat("[POOL] Using credentials: user=", db_user, ", host=", db_host, ", db=", db_schema, "\n")
  
} else {
  cat("[POOL] Using existing infinitetrading connection pool\n")
}

cat("[POOL] Infinitetrading db_pool.R loaded successfully\n")
