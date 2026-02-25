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
delete_table <- function(table_name) {
  cnx <- db_con()
  query <- paste("DROP TABLE IF EXISTS", dbQuoteIdentifier(cnx, Sys.getenv("db_schema")), ".", dbQuoteIdentifier(cnx, table_name))
  dbExecute(cnx, query)
  print(paste0("table: ",table_name,"  deleted"))
  dbDisconnect(cnx)
}
print("deleting all tables")
tables = c("coins","uniV3Fees","pairs","networks","protocols","polygon_dhedge_sides","polygon_dhedge_gas_wallets")
print(tables)
for (table in tables) { delete_table(table) }
dbDisconnect(conn)
