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

add_platforms <- function(conn, platform_names) {
  platform_names = tolower(platform_names)
  for (platform_name in platform_names) {
    exists <- dbGetQuery(conn, "SELECT COUNT(*) as count FROM platforms WHERE name = ?", params = list(platform_name))
    if (exists$count == 0) {
      dbExecute(conn, "INSERT INTO platforms (name) VALUES (?)", params = list(platform_name))
    } else {
      message("Platform already exists: ", platform_name)
    }
  }
}
remove_platforms <- function(conn, platform_names) { for (platform_name in platform_names) { dbExecute(conn, "DELETE FROM platforms WHERE name = ?", params = list(tolower(platform_name))) } }
is_valid_platform <- function(platform) {
  conn = db_con()
  query <- sprintf("SELECT COUNT(*) as count FROM platforms WHERE name = LOWER(?)", platform)
  result <- dbGetQuery(conn, query, params = list(platform))
  dbDisconnect(conn)
  return(result$count > 0)
}

#add_platforms(c("uniswapV3","1inch"))
#remove_platforms("1inch"))
#print(is_valid_platfom("uniswapV3"))
print(dbReadTable(conn, "platforms"))
dbDisconnect(conn)
