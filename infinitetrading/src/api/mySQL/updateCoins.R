require(RMariaDB); require(DBI); require(dotenv)
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

add_coin <- function(conn, network, symbol, contract) {
  network <- tolower(network); symbol <- tolower(symbol); contract <- tolower(contract); symbol <- toupper(symbol)
  network_id_query <- dbGetQuery(conn, "SELECT network_id FROM networks WHERE name = ?", params = list(network))
  if (nrow(network_id_query) == 0) return("Network not found")
  network_id <- network_id_query$network_id
  insert_query <- "INSERT INTO coins (symbol, network_id, contract) VALUES (?, ?, ?)
          ON DUPLICATE KEY UPDATE symbol = VALUES(symbol), network_id = VALUES(network_id)"
  dbExecute(conn, insert_query, params = list(symbol, network_id, contract))
}

getCoins <- function(conn) {
  result <- dbGetQuery(conn, "SELECT c.symbol, n.name AS network, c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id")
  if (nrow(result) == 0) return("No coins found in the database.")
  return(result)
}

getContract <- function(conn, symbol, network) {
  symbol <- tolower(symbol); network <- tolower(network)
  contract_query <- dbGetQuery(conn, "SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?", params = list(symbol, network))
  if (nrow(contract_query) == 0) { return("No contract found for the given symbol and network") }
  return(contract_query$contract)
}

getSymbol <- function(conn, contract, network) {
  contract <- tolower(contract); network <- tolower(network)
  symbol_query <- dbGetQuery(conn, "SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?", params = list(contract, network))
  if (nrow(symbol_query) == 0) return("No symbol found for the given contract and network")
  return(symbol_query$symbol)
}

updateCoins <- function() {
        coins_data <- read.csv("/home/ubuntu/infinitetrading/coins.csv", stringsAsFactors = FALSE,colClasses = c("character", "character", "character"))
        for (i in seq_len(nrow(coins_data))) { add_coin(conn, coins_data$network[i], coins_data$symbol[i], coins_data$contract[i]) }
}

updateCoins()

#with ids
#print(dbReadTable(conn, "coins"))

#with network names
print(getCoins(conn))

dbDisconnect(conn)
