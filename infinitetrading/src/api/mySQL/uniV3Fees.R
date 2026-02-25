require(dotenv); require(RMariaDB); require(DBI)
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

add_fees <- function(conn, network, pairs,fees) {
  network_name <- tolower(network)
  network_id <- dbGetQuery(conn, "SELECT network_id FROM networks WHERE name = ?", params = list(network))
  n = length(pairs)
  if (nrow(network_id) > 0) {
    network_id = network_id$network_id
    for (i in 1:n) {
      pair <- toupper(pairs[i])
      fee <- as.integer(fees[i])
      pair_id <- dbGetQuery(conn, "SELECT pair_id FROM pairs WHERE network_id = ? AND pair = ?", params = list(network_id, pair))
      if (nrow(pair_id) > 0) {
        pair_id = pair_id$pair_id
        # Insert or update fee
        dbExecute(conn, "INSERT INTO uniV3Fees (pair_id, network_id, fee) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE fee = ?", params = list(pair_id, network_id, fee, fee))
      } else {
        message("Pair does not exist, cannot add fee: ", pair)
      }
    }
  } else {
    stop("Network not found")
  }
}
remove_fees <- function(conn, network, pairs) {
  network_name <- tolower(network)
  network_id <- dbGetQuery(conn, "SELECT network_id FROM networks WHERE name = ?", params = list(network_name))
  network_id = network_id$network_id
  if (nrow(network_id) > 0) {
    for (pair_name in pairs) {
      pair_name <- tolower(pair_name)
      pair_id <- dbGetQuery(conn, "SELECT pair_id FROM pairs WHERE network_id = ? AND pair = ?", params = list(network_id, pair_name))
      pair_id = pair_id$pair_id
      if (nrow(pair_id) > 0) { dbExecute(conn, "DELETE FROM uniV3Fees WHERE pair_id = ? AND network_id = ?", params = list(pair_id, network_id)) }
      else { return("Pair does not exist, cannot remove fee: ", pair_name) }
    }
  }
  else { return("Network not found") }
}

getUniV3Fee <- function(network, pair) {
  conn = db_con()
  network = tolower(network)
  pair=toupper(pair)
  # SQL to find network_id
  network_id_query <- sprintf("SELECT network_id FROM networks WHERE name = '%s'", network)
  network_id <- dbGetQuery(conn, network_id_query)$network_id
  if (length(network_id) == 0) { res = "Network not found" }
  else {
        pair_id_query <- sprintf("SELECT pair_id FROM pairs WHERE network_id = %d AND pair = '%s'", network_id, pair)
        pair_id <- dbGetQuery(conn, pair_id_query)$pair_id
        if (length(pair_id) == 0) res = "Pair not found"
        else {
                fee_query <- sprintf("SELECT fee FROM uniV3Fees WHERE network_id = %d AND pair_id = %d", network_id, pair_id)
                fee_amount <- dbGetQuery(conn, fee_query)$fee
                if (length(fee_amount) == 0) res = "Fee not found"
                else res = fee_amount
        }
  }
  dbDisconnect(conn)
  return(res)
}

#add_fees(conn, network="optimism",pairs=c("WETH-USDC"),c(500))
#with ids
#add_fees(conn, network="optimism",pairs=c("WBTC-USDC"),c(3000))
print(dbReadTable(conn, "uniV3Fees"))
#with names
printUniV3Fees <- function() {
  # Establish connection to the database
  conn <- db_con()

  # Define the SQL query
  query <- "
    SELECT
      n.name AS network_name,
      p.pair AS pair_name,
      f.fee
    FROM
      uniV3Fees f
      JOIN networks n ON f.network_id = n.network_id
      JOIN pairs p ON f.pair_id = p.pair_id
  "

  # Execute the query and fetch results
  result <- dbGetQuery(conn, query)

  # Check if the result is empty
  if (nrow(result) == 0) {
    message("No fees found in the database.")
  } else {
    print(result)
  }

  # Disconnect from the database
  dbDisconnect(conn)
}

# Optionally, call the function to see the output
printUniV3Fees()

dbDisconnect(conn)
