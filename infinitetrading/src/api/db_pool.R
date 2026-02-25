# Database Connection Pool for R
# Uses the 'pool' package to manage RDS connections efficiently
# This prevents connection leaks and reduces total connection count

library(pool)
library(RMariaDB)

# Create a global connection pool
# Pool will maintain connections and reuse them across requests
# RDS max_connections = 30, using 15 for pool (50%) to leave room for other services
# POOLING DISABLED - Using direct connections instead
# POOLING DISABLED - Using direct connections instead
# # db_pool <- pool::dbPool(
# #   drv = RMariaDB::MariaDB(),
# #   host = Sys.getenv("db_ip"),
# #   port = as.integer(Sys.getenv("db_port")),
# #   user = Sys.getenv("db_user"),
# #   password = Sys.getenv("db_password"),
# #   dbname = Sys.getenv("db_schema"),
# #   minSize = 3,      # Minimum connections to keep alive
# #   maxSize = 15,     # Maximum connections in pool (RDS max is 30)
# #   idleTimeout = 300 # Close idle connections after 5 minutes
# # )
# # 
# # # Get a connection from the pool
# # # This connection will automatically be returned to the pool when done
# # get_pool_connection <- function(db = NULL) {
# #   if (!is.null(db)) {
# #     # If a specific database is requested, create a temporary pool
# #     # (or you can extend this to support multiple pools)
# #     warning("Specific database requested, using new connection instead of pool")
# #     return(dbConnect(
# #       RMariaDB::MariaDB(),
# #       host = Sys.getenv("db_ip"),
# #       port = as.integer(Sys.getenv("db_port")),
# #       user = Sys.getenv("db_user"),
# #       password = Sys.getenv("db_password"),
# #       dbname = db
# #     ))
  }
  
  # Return the pool object directly - DBI functions will auto-manage connections
  # NEVER use poolCheckout() without poolReturn() - it causes connection leaks!
  return(db_pool)
}

# Cleanup function to be called on script exit
cleanup_pool <- function() {
  tryCatch({
    poolClose(db_pool)
    message("Database connection pool closed successfully")
  }, error = function(e) {
    warning(paste("Error closing pool:", e$message))
  })
}

# Register cleanup function
reg.finalizer(environment(), function(e) cleanup_pool(), onexit = TRUE)

cat("Database connection pool initialized with min=2, max=5 connections\n")
