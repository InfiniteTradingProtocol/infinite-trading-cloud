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

add_pairs <- function(conn, network_name, pairs) {
  network_name = tolower(network_name); pairs = toupper(pairs)
  network_id <- dbGetQuery(conn, "SELECT network_id FROM networks WHERE name = ?", params = list(network_name))
  if (nrow(network_id) > 0) {
    for (pair in pairs) {
      exists <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM pairs WHERE network_id = ? AND pair = ?", params = list(network_id$network_id, pair))
      if (exists$count == 0) {
        dbExecute(conn, "INSERT INTO pairs (network_id, pair) VALUES (?, ?)", params = list(network_id$network_id, pair))
      } else {
        message("Pair already exists for this network: ", pair)
      }
    }
  } else {
    stop("Network not found")
  }
}

remove_pairs <- function(conn, network_name, pairs) {
  network_name = tolower(network_name); pairs = toupper(pairs)
  network_id <- dbGetQuery(conn, "SELECT network_id FROM networks WHERE name = ?", params = list(network_name))
  if (nrow(network_id) > 0) {
    for (pair in pairs) { dbExecute(conn, "DELETE FROM pairs WHERE network_id = ? AND pair = ?", params = list(network_id$network_id, pair)) }
  } else { return("Network not found") }
}

is_valid_pair <- function(network, pair) {
  conn = db_con()
  query <- "SELECT COUNT(*) as count FROM pairs p JOIN networks n ON p.network_id = n.network_id WHERE n.name = LOWER(?) AND p.pair = ?"
  result <- dbGetQuery(conn, query, params = list(network, pair))
  dbDisconnect(conn)
  return(result$count > 0)
}

#add_pairs(conn,"polygon","WBTC-USDC"))
#add_pairs(conn,"optimism","TBTC-USDC")
##with ids
#print(dbReadTable(conn, "pairs"))
#with names
printPairsTable <- function() {
  # Establish connection to the database
  conn <- db_con()

  # Define the SQL query
  query <- "
    SELECT
      n.name AS network_name,
      p.pair AS pair
    FROM
      pairs p
      JOIN networks n ON p.network_id = n.network_id
  "

  # Execute the query and fetch results
  result <- dbGetQuery(conn, query)

  # Check if the result is empty
  if (nrow(result) == 0) {
    message("No pairs found in the database.")
  } else {
    print(result)
  }

  # Disconnect from the database
  dbDisconnect(conn)
}

# Optionally, call the function to see the output
printPairsTable()
dbDisconnect(conn)
