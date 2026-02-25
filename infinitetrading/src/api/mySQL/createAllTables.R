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

sql_networks <- "
CREATE TABLE IF NOT EXISTS networks (
    network_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) UNIQUE
);"

sql_protocols <- "
CREATE TABLE IF NOT EXISTS protocols (
    protocol_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) UNIQUE
);"

sql_platforms <- "
CREATE TABLE IF NOT EXISTS platforms (
    platform_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) UNIQUE
);"

sql_pairs <- "
CREATE TABLE IF NOT EXISTS pairs (
    pair_id INT AUTO_INCREMENT PRIMARY KEY,
    network_id INT,
    pair VARCHAR(255),
    FOREIGN KEY (network_id) REFERENCES networks(network_id),
    UNIQUE (network_id, pair)
);"

sql_fees <- "
CREATE TABLE IF NOT EXISTS uniV3Fees (
    pair_id INT,
    network_id INT,
    fee INT,
    PRIMARY KEY (pair_id, network_id),
    FOREIGN KEY (pair_id) REFERENCES pairs(pair_id),
    FOREIGN KEY (network_id) REFERENCES networks(network_id)
);"
sql_coins <- "
CREATE TABLE IF NOT EXISTS coins (
    symbol VARCHAR(50),
    network_id INT,
    contract VARCHAR(100) UNIQUE,
    PRIMARY KEY (symbol, network_id),
    FOREIGN KEY (network_id) REFERENCES networks(network_id)
);"

create_table <- function(query,conn=NULL) {
  tryCatch({
    if (is.null(conn)) { conn = db_con() }
    res = dbExecute(conn, query)
    print(res)
    message("Table created successfully or already exists.")
  }, error = function(e) {
    message("Error creating table: ", e$message)
  })
}

queries = c(
	    sql_networks,
	    sql_protocols, 
	    sql_pairs, 
	    sql_platforms,
	    sql_fees, 
	    sql_coins
)
for (query in queries) { create_table(query,conn) }

dbDisconnect(con)

