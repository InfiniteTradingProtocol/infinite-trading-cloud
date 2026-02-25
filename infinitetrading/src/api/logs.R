require(plumber); require(data.table); require(DBI); require(RSQLite); require(lubridate); require(jsonlite); require(httr);
# Initialize SQLite database
db <- RSQLite::dbConnect(SQLite(), "api_logs.sqlite")
RSQLite::dbExecute(db, "
  CREATE TABLE IF NOT EXISTS api_logs (
    id INTEGER PRIMARY KEY,
    timestamp TEXT,
    endpoint TEXT,
    api_key TEXT,
    ip TEXT
  )
")
