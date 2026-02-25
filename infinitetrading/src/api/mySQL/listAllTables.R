require(dotenv);require(RMariaDB);require(DBI)
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
print("listing all tables")
allTables = dbListTables(conn)

print_table_structure <- function(conn, table_name) {
  safe_table_name <- gsub("'", "''", table_name)  # Simple quote escaping
  # Use DBI::dbQuoteIdentifier for better handling (if supported by your DBI driver)
  safe_table_name <- DBI::dbQuoteIdentifier(conn, table_name)
  query <- sprintf("DESCRIBE %s", safe_table_name)
  result <- dbGetQuery(conn, query)
  if (nrow(result) == 0) message("No such table found or no permission to access the table: ", table_name)
  else print(result)
}

for (table in allTables) {
	print(paste0("table name:",table))
	print_table_structure(conn,as.character(table))
}
dbDisconnect(conn)
