require(dotenv);require(RMariaDB); require(DBI)
load_dot_env("~/infinitetrading/src/api/.env")

db_connect = function(user,hostname,port,password,dbname){
        default_authentication_plugin=password
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname,hostname = hostname)
        return(con)
}
db_con = function() {
        con = db_connect(Sys.getenv("db_user"),Sys.getenv("db_ip"),Sys.getenv("db_port"),Sys.getenv("db_password"),dbname=Sys.getenv("db_schema"))
        return(con)
}

conn = db_con()

add_networks <- function(conn, network_names) {
  network_names = tolower(network_names)
  for (network_name in network_names) {
    exists <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM networks WHERE name = ?", params = list(network_name))
    if (exists$count == 0) {
      dbExecute(conn, "INSERT INTO networks (name) VALUES (?)", params = list(network_name))
    } else {
      message("Network already exists: ", network_name)
    }
  }
}
remove_networks <- function(conn, network_names) { for (network_name in network_names) { dbExecute(conn, "DELETE FROM networks WHERE name = ?", params = list(tolower(network_name))) } }

is_valid_network <- function(network) {
  conn = db_con()
  query <- sprintf("SELECT COUNT(*) as count FROM networks WHERE name = LOWER(?)", network)
  result <- dbGetQuery(conn, query, params = list(network))
  dbDisconnect(conn)
  return(result$count > 0)
}

# Add all required networks (safe to re-run – skips existing entries)
add_networks(conn, c("optimism", "polygon", "arbitrum", "base", "ethereum", "mainnet", "hyperliquid"))

print(dbReadTable(conn, "networks"))
dbDisconnect(conn)
