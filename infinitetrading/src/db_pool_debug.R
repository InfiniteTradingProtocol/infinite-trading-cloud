# Test pool creation with verbose errors
library(pool)
library(RMariaDB)
library(dotenv)

load_dot_env("/home/ubuntu/infinitetrading/src/.env")

db_user <- Sys.getenv("db_user")
db_password <- Sys.getenv("db_password")
db_host <- Sys.getenv("db_host")
db_schema <- Sys.getenv("db_schema")

cat("Attempting pool creation with:\n")
cat("  User:", db_user, "\n")
cat("  Host:", db_host, "\n")
cat("  Schema:", db_schema, "\n")

tryCatch({
  test_pool <- pool::dbPool(
    drv = RMariaDB::MariaDB(),
    user = db_user,
    password = db_password,
    host = db_host,
    port = 3306,
    dbname = db_schema,
    minSize = 1,
    maxSize = 2
  )
  cat("✅ Pool created successfully!\n")
  poolClose(test_pool)
}, error = function(e) {
  cat("❌ Pool creation failed:\n")
  cat("  Error:", conditionMessage(e), "\n")
  cat("  Call:", deparse(conditionCall(e)), "\n")
})
