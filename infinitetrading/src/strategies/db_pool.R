# Database Connection Pool for Strategy Scripts
# Uses the 'pool' package to manage RDS connections efficiently

library(pool)
library(RMariaDB)

# Create a global connection pool
db_pool <- pool::dbPool(
  drv = RMariaDB::MariaDB(),
  host = Sys.getenv("db_ip"),
  port = as.integer(Sys.getenv("db_port", "3306")),
  user = Sys.getenv("db_user"),
  password = Sys.getenv("db_password"),
  dbname = "infinitetrading",
  minSize = 1,      # Strategies need fewer connections
  maxSize = 3,      # Max 3 per strategy
  idleTimeout = 300 # Close idle connections after 5 minutes
)

# Cleanup function
cleanup_pool <- function() {
  tryCatch({
    poolClose(db_pool)
  }, error = function(e) {
    warning(paste("Error closing pool:", e$message))
  })
}

reg.finalizer(environment(), function(e) cleanup_pool(), onexit = TRUE)

cat("Strategy database pool initialized (min=1, max=3)\n")
