library(RMariaDB)
library(DBI)
library(lubridate)

candles <- function(pair, timeframe) {
  # Establishing database connection
  con <- dbConnect(RMariaDB::MariaDB(),
                   user = "richard_clare",
                   password = "AxDWeW8E7w8dSXJKsXsdfASXaxAD279347",
                   dbname = "infinitetrading",
                   host = "localhost")
  
  # Creating table name
  table_name <- paste0("`",pair, "_", timeframe,"`")
  
  # Querying the data from the table
  query <- paste0("SELECT * FROM ", table_name)
  data <- dbGetQuery(con, query)
  data = as.data.frame(data)
  data = data[,-1]
  colnames = c("time","low","high","open","close","volume")
  # Closing the database connection
  dbDisconnect(con)
  return(data)
}
#Pulling candles from the database (example: BTC-USD, 6h timeframe)
data = candles("BTC-USD", "6h")
print(data)
# Printing the retrieved data
#wd = "/home/ubuntu/GitHub/Tradery-Development/"
#source(paste(wd,"basic.R",sep=""))
##reference(c("ml/ml_indicators.R","ml/ml_indicators_hades.R"))
#require(reticulate); require(quantmod); require(TTR); require(httr); require(rgdax); require(jsonlite); require(lubridate); require(snakecase); require(stringr); require(caret)

