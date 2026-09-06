# Local MySQL Helper Functions for Infinite Trading
# Provides connection to LOCAL MySQL for ephemeral data (predictions, messages)
# Keeps ephemeral local data separate from the main persistent database

require(DBI)
require(RMariaDB)

#' Get connection to LOCAL MySQL (127.0.0.1)
#' Used for: predictions, stoplosses, messages
#' @param db Database name (default: "infinitetrading")
#' @return MySQL connection object
local_db_con <- function(db = "infinitetrading") {
  tryCatch({
    # Get credentials from environment variables (LOCAL MySQL)
    db_user <- Sys.getenv("db_user_local")
    db_password <- Sys.getenv("db_password_local")
    
    if (db_user == "" || db_password == "") {
      stop("Missing db_user_local or db_password_local environment variables")
    }
    
    con <- dbConnect(
      RMariaDB::MariaDB(),
      user = db_user,
      password = db_password,
      dbname = db,
      host = "127.0.0.1",
      port = 3306
    )
    return(con)
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to connect to local MySQL:", e$message, "\n")
    stop("Local MySQL connection failed. Is MySQL running locally?")
  })
}

#' Write data to local MySQL table
#' @param df Data frame to write
#' @param table_name Table name
#' @param append Whether to append (default: TRUE)
#' @return 1L on success, 0L on failure
local_write_table <- function(df, table_name, append = TRUE) {
  tryCatch({
    con <- local_db_con()
    on.exit(dbDisconnect(con), add = TRUE)
    
    dbWriteTable(con, table_name, df, append = append, row.names = FALSE)
    cat("[LOCAL DB] Wrote", nrow(df), "rows to", table_name, "\n")
    return(1L)
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to write to", table_name, ":", e$message, "\n")
    return(0L)
  })
}

#' Read data from local MySQL table
#' @param table_name Table name
#' @param query Optional SQL query (if NULL, reads entire table)
#' @return Data frame or NULL on error
local_read_table <- function(table_name = NULL, query = NULL) {
  tryCatch({
    con <- local_db_con()
    on.exit(dbDisconnect(con), add = TRUE)
    
    if (!is.null(query)) {
      result <- dbGetQuery(con, query)
    } else if (!is.null(table_name)) {
      result <- dbReadTable(con, table_name)
    } else {
      stop("Must provide either table_name or query")
    }
    
    return(result)
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to read:", e$message, "\n")
    return(NULL)
  })
}

#' Store ML model prediction in local MySQL
#' @param symbol Trading symbol (e.g., "BTC-USD")
#' @param prediction Prediction value
#' @param stoploss Optional stoploss value
#' @param model_name Optional model name
#' @return 1L on success, 0L on failure
local_store_prediction <- function(symbol, prediction, stoploss = NULL, model_name = "default") {
  tryCatch({
    con <- local_db_con()
    on.exit(dbDisconnect(con), add = TRUE)
    
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    
    # Insert or update prediction
    query <- sprintf(
      "INSERT INTO predictions (symbol, model_name, prediction, stoploss, timestamp) 
       VALUES ('%s', '%s', %f, %s, '%s')
       ON DUPLICATE KEY UPDATE 
       prediction = VALUES(prediction),
       stoploss = VALUES(stoploss),
       timestamp = VALUES(timestamp)",
      symbol, model_name, prediction,
      ifelse(is.null(stoploss), "NULL", stoploss),
      timestamp
    )
    
    dbExecute(con, query)
    cat("[LOCAL DB] Stored prediction for", symbol, ":", prediction, "\n")
    return(1L)
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to store prediction:", e$message, "\n")
    return(0L)
  })
}

#' Get ML model prediction from local MySQL
#' @param symbol Trading symbol (e.g., "BTC-USD")
#' @param model_name Optional model name (default: "default")
#' @return List with prediction, stoploss, timestamp or NULL
local_get_prediction <- function(symbol, model_name = "default") {
  tryCatch({
    con <- local_db_con()
    on.exit(dbDisconnect(con), add = TRUE)
    
    query <- sprintf(
      "SELECT prediction, stoploss, timestamp 
       FROM predictions 
       WHERE symbol = '%s' AND model_name = '%s'
       ORDER BY timestamp DESC LIMIT 1",
      symbol, model_name
    )
    
    result <- dbGetQuery(con, query)
    
    if (nrow(result) == 0) {
      return(NULL)
    }
    
    return(list(
      prediction = result$prediction[1],
      stoploss = result$stoploss[1],
      timestamp = result$timestamp[1]
    ))
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to get prediction:", e$message, "\n")
    return(NULL)
  })
}

#' Push message to local MySQL (for Discord/Slack notifications)
#' @param platform 'discord' or 'slack'
#' @param channel Channel name (e.g., '#error-logs')
#' @param message Message content
#' @return TRUE on success, FALSE on failure
local_push_message <- function(platform, channel, message) {
  tryCatch({
    con <- local_db_con()
    on.exit(dbDisconnect(con), add = TRUE)
    
    # Truncate message if too long
    if (nchar(message)[1] > 255) {
      message <- substr(message, 1, 255)
    }
    
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%OS9")
    insert_query <- sprintf(
      "INSERT IGNORE INTO messages (timestamp, platform, channel, message) VALUES ('%s','%s', '%s', '%s')",
      timestamp, platform, channel, message
    )
    
    dbExecute(con, insert_query, append = TRUE)
    cat("[LOCAL DB] Message pushed to", platform, "queue\n")
    return(TRUE)
  }, error = function(e) {
    cat("[LOCAL DB ERROR] Failed to push message:", e$message, "\n")
    return(FALSE)
  })
}

#' Discord notification using local MySQL
#' @param msg Message content
#' @param channel Discord channel (default: "#dhedge-pools")
#' @param db Whether to store in database (default: TRUE)
discord_local <- function(msg, channel = "#dhedge-pools", db = TRUE) {
  if (db) {
    result <- tryCatch({
      local_push_message(platform = "discord", channel = channel, message = msg)
      Sys.sleep(0.0001)
    }, error = function(e) {
      cat("[DISCORD ERROR]:", e$message, "\n")
    })
  } else {
    cat("[DISCORD] (no DB):", channel, "-", msg, "\n")
  }
}

cat("[LOCAL DB] Helper functions loaded - Use for predictions/stoplosses/messages\n")
cat("[LOCAL DB] For persistent data, continue using db_con()\n")
