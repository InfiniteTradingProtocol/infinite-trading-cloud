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

add_protocols <- function(conn, protocol_names) {
  protocol_names = tolower(protocol_names)
  for (protocol_name in protocol_names) {
    exists <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM protocols WHERE name = ?", params = list(protocol_name))
    if (exists$count == 0) {
      dbExecute(conn, "INSERT INTO protocols (name) VALUES (?)", params = list(protocol_name))
    } else {
      message("Protocol already exists: ", protocol_name)
    }
  }
}

remove_protocols <- function(conn, protocol_names) { for (protocol_name in protocol_names) { dbExecute(conn, "DELETE FROM protocols WHERE name = ?", params = list(tolower(protocol_name))) } }

is_valid_protocol <- function(protocol) {
  conn = db_con()
  query <- sprintf("SELECT COUNT(*) as count FROM protocols WHERE name = LOWER(?)", protocol)
  result <- dbGetQuery(conn, query, params = list(protocol))
  dbDisconnect(conn)
  return(result$count > 0)
}


#add_protocols("dhedge","enzyme")
#remove_protocols("enzyme")
#print(is_valid_protocol("dhedge"))
#print(is_valid_protocol("enzyme"))
print(dbReadTable(conn, "protocols"))

dbDisconnect(conn)
