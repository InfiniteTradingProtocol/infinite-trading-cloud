#########################
## Databases management #
## Author: etherpilled  #
## Infinite Trading     #
#########################

require(DBI); require(RMariaDB); require(dotenv); require(redux)

# Load consolidated .env from repo root
tryCatch({
  if (exists("wd") && file.exists(paste0(wd, ".env"))) {
    load_dot_env(paste0(wd, ".env"))
  } else if (file.exists(".env")) {
    load_dot_env(".env")
  } else if (file.exists("../.env")) {
    load_dot_env("../.env")
  } else if (file.exists("../../.env")) {
    load_dot_env("../../.env")
  }
  cat("✅ Loaded .env successfully\n")
  cat(sprintf("   DB Host: %s, Port: %s, User: %s, Schema: %s\n",
              Sys.getenv("db_ip"), Sys.getenv("db_port"),
              Sys.getenv("db_user"), Sys.getenv("db_schema")))
}, error=function(e) {
  cat("⚠️  No .env file found - using system environment variables\n")
  cat(sprintf("   DB Host: %s, Port: %s, User: %s, Schema: %s\n",
              Sys.getenv("db_ip"), Sys.getenv("db_port"),
              Sys.getenv("db_user"), Sys.getenv("db_schema")))
})

# source("~/infinitetrading/src/api/encryption.R")  # Now sourced from parent
# source("~/infinitetrading/src/api/helpers/yieldPools.R")  # Optional
r <- redux::hiredis()

####################
# CACHE SYSTEM
####################

# Initialize cache on startup - load static data once
.cache_env <- new.env()

cache_init <- function() {
  tryCatch({
    # Cache networks (rarely change)
    con <- db_con()
    networks <- dbGetQuery(con, "SELECT LOWER(name) as name FROM networks")
    .cache_env$valid_networks <- networks$name

    # Cache protocols (rarely change)
    protocols <- dbGetQuery(con, "SELECT LOWER(name) as name FROM protocols")
    .cache_env$valid_protocols <- protocols$name

    # Cache pairs with network mapping (update every 5 minutes via scheduled task)
    pairs <- dbGetQuery(con, "SELECT LOWER(n.name) as network, p.pair FROM pairs p JOIN networks n ON p.network_id = n.network_id")
    .cache_env$valid_pairs <- pairs

    .cache_env$cache_time <- Sys.time()
    cat(sprintf("✅ Cache initialized: %d networks, %d protocols, %d pairs\n",
                length(.cache_env$valid_networks),
                length(.cache_env$valid_protocols),
                nrow(.cache_env$valid_pairs)))
  }, error = function(e) {
    cat("⚠️  Cache initialization failed:", e$message, "\n")
    .cache_env$valid_networks <- character(0)
    .cache_env$valid_protocols <- character(0)
    .cache_env$valid_pairs <- data.frame(network=character(0), pair=character(0))
  })
}

# Refresh cache if older than 24 hours
cache_refresh_if_needed <- function() {
  if (is.null(.cache_env$cache_time) ||
      difftime(Sys.time(), .cache_env$cache_time, units="hours") > 24) {
    cache_init()
  }
}

####################
# BASIC MYSQL CODE
####################

# Legacy connection function - kept for compatibility
db_connect = function(user,hostname,port,password,dbname){
        default_authentication_plugin=password
        # Ensure port is integer and hostname is provided
        if (is.character(port)) port <- as.integer(port)
        if (is.null(hostname) || hostname == "") hostname <- "127.0.0.1"
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname, host = hostname, port = port)
        return(con)
}

# Connection function - always returns direct connection (pooling removed)
db_con = function(db=NULL) {
        if (is.null(db)) { db = Sys.getenv("db_schema") }
        return(db_connect(Sys.getenv("db_user"),Sys.getenv("db_ip"),Sys.getenv("db_port"),Sys.getenv("db_password"),dbname=db))
}

read_table = function(db=NULL,table_name) {
        cnx = db_con(db=db)
        on.exit(tryCatch(dbDisconnect(cnx), error = function(e) {}), add=TRUE)
        if (!dbExistsTable(cnx,sprintf('%s',table_name))){ return(print(sprintf("Table '%s' does not exist, please make sure your table is created into your MySQL",table_name))) }
        table_content = c()
        table_content = RMariaDB::dbReadTable(cnx,sprintf('%s',table_name))
        return(table_content)
}

delete_table <- function(table_name) {
  cnx <- db_con()
  on.exit(tryCatch(dbDisconnect(cnx), error = function(e) {}), add=TRUE)
  query <- paste("DROP TABLE IF EXISTS", dbQuoteIdentifier(cnx, Sys.getenv("db_schema")), ".", dbQuoteIdentifier(cnx, table_name))
  dbExecute(cnx, query)
  print(paste0("table: ",table_name,"  deleted"))
}

write_table = function(schema=NULL,table, names, types, values, primary_key, print=FALSE, append=FALSE) {
    cnx <- NULL
    result_status <- 0L  # Use integer: 1L = success, 0L = fail

    tryCatch({
        # Force direct connection for write operations to avoid pool exhaustion
        cnx <- db_con(db=schema)

        n <- length(names)
        dbBegin(cnx)  # Start transaction
        if (!dbExistsTable(cnx, table)) {
            query <- sprintf("CREATE TABLE `%s` (", table)
            for (i in 1:n) {
                query <- sprintf("%s`%s` %s NOT NULL,", query, names[i], types[i])
            }
            primary_key_clause <- paste(sprintf("`%s`", primary_key), collapse = ", ")
            query <- sprintf("%s PRIMARY KEY (%s));", query, primary_key_clause)
            if (print) print(query)
            dbExecute(cnx, query)
        }
        query <- sprintf("INSERT INTO `%s` (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s;",
                         table,
                         paste(sprintf("`%s`", names), collapse = ","),
                         paste(sapply(1:n, function(i) if (grepl("VARCHAR", types[i])) sprintf("'%s'", values[i]) else as.character(values[i])), collapse = ","),
                         paste(sapply(1:n, function(i) sprintf("`%s` = VALUES(`%s`)", names[i], names[i])), collapse = ","))

        if (print) print(query)
        dbExecute(cnx, query)
        dbCommit(cnx)
        result_status <- 1L  # Success
    }, error = function(e) {
        cat("An error occurred in write_table: ", e$message, " | Class: ", class(e), "\n")
        result_status <<- 0L  # Fail
    })

    # Clean up connection
    if (!is.null(cnx)) tryCatch(dbDisconnect(cnx), error = function(e) {})

    # Return integer code
    return(result_status)
}


rename_table <- function(name, new_name) {
    result <- tryCatch({
        con <- db_con()
        on.exit(dbDisconnect(con), add = TRUE)
        rename_query <- sprintf("RENAME TABLE %s TO %s;", name, new_name)
        dbExecute(con, rename_query)
    }, error = function(e) {
        paste("An error occurred:", e$message)
    })
    return(result)
}

alterTableStructure <- function(query) {
    con <- db_con()
    on.exit(dbDisconnect(con), add = TRUE)  # Ensure disconnection on exit
    result <- tryCatch({
        dbExecute(con, query)
    }, error = function(e) {
        paste("An error occurred: ", e$message)
    })
    return(result)
}

#alterTableStructure("ALTER TABLE polygon_dhedge_sides ADD platform VARCHAR(30);")

is_valid_network <- function(network) {
    	# OPTIMIZED: Use in-memory cache instead of database query
    	cache_refresh_if_needed()
    	return(tolower(network) %in% .cache_env$valid_networks)
}

is_valid_network_with_query = function(network) {
        query <- "SELECT COUNT(*) as count FROM networks WHERE name = LOWER(?)"
	result = send_query(query,params=list(network))
	return(result$count>0)
}

is_valid_protocol <- function(protocol) {
  	# OPTIMIZED: Use in-memory cache instead of database query
  	cache_refresh_if_needed()
  	return(tolower(protocol) %in% .cache_env$valid_protocols)
}

is_valid_pair <- function(network, pair) {
	# OPTIMIZED: Use in-memory cache instead of database query
	cache_refresh_if_needed()
	network_lower <- tolower(network)
	matches <- .cache_env$valid_pairs[.cache_env$valid_pairs$network == network_lower & .cache_env$valid_pairs$pair == pair, ]
      	return(nrow(matches) > 0)
}

####################
# API CODE
####################

setAllocations = function(protocol,pool,network,assets,allocations,upper_thresholds,lower_thresholds,slippages,max_usd,platform) {
	response <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		query <- "INSERT INTO dhedge_allocations (network, pool, assets, allocations, upper_thresholds, lower_thresholds)
		          VALUES (?, ?, ?, ?, ?, ?)
		          ON DUPLICATE KEY UPDATE assets=VALUES(assets), allocations=VALUES(allocations),
		          upper_thresholds=VALUES(upper_thresholds), lower_thresholds=VALUES(lower_thresholds)"
		dbExecute(con, query, params = list(network, pool, assets, allocations, upper_thresholds, lower_thresholds))
		list(status="success", status_code=200, message="Allocations submitted successfully")
	},
	error = function(e) {
		cat("Error: setAllocations for protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error submitting allocations")
	})
	return(response)
}

setSide <- function(protocol, pool, network, pair, side, threshold, max_usd, share, platform, slippage, lending=FALSE) {
	response <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool); pair <- toupper(pair)
		query <- "INSERT INTO dhedge_sides (network, pool, pair, side, threshold, max_usd, share, platform, slippage)
		          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		          ON DUPLICATE KEY UPDATE side=VALUES(side), threshold=VALUES(threshold),
		          max_usd=VALUES(max_usd), share=VALUES(share), platform=VALUES(platform), slippage=VALUES(slippage)"
		dbExecute(con, query, params = list(network, pool, pair, side, as.numeric(threshold), as.integer(max_usd), as.numeric(share), platform, as.numeric(slippage)))
		list(status="success", status_code=200, message="Sides submitted successfully")
	},
	error = function(e) {
		cat("Error: setSide for protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error submitting sides")
	})
	return(response)
}

deleteBot = function(protocol, pool, network) {
    result <- tryCatch({
        con <- db_con()
        on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
        network <- tolower(network); pool <- tolower(pool)
        dbExecute(con, "DELETE FROM dhedge_sides WHERE network = ? AND pool = ?", params = list(network, pool))
        list(status = "success", status_code = 200, message = paste("Bot successfully deleted:", pool))
    },
    error = function(e) {
        cat("Error: deleteBot for protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
        list(status = "fail", status_code = 500, message = "Internal error deleting bot entry")
    })
    return(result)
}

getSide = function(protocol, pool, network) {
	sides <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		result <- dbGetQuery(con, "SELECT pair, side, threshold, max_usd, share, platform, slippage FROM dhedge_sides WHERE network = ? AND pool = ?",
		                     params = list(network, pool))
		list(status="success", status_code=200, message=result)
	},
	error = function(e) {
		cat("Error: getSide for protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error getting sides")
	})
	return(sides)
}

getSides <- function(protocol, network) {
	sides <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network)
		result <- dbGetQuery(con, "SELECT pool, pair, side, threshold, max_usd, share, platform, slippage FROM dhedge_sides WHERE network = ?",
		                     params = list(network))
		list(status="success", status_code=200, message=result)
	},
	error = function(e) {
		cat("Error: getSides for protocol:", protocol, "network:", network, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error getting sides")
	})
	return(sides)
}

getAllocations <- function(protocol, pool, network) {
	allocations <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		result <- dbGetQuery(con, "SELECT assets, allocations, upper_thresholds, lower_thresholds FROM dhedge_allocations WHERE network = ? AND pool = ?",
		                     params = list(network, pool))
		list(status="success", status_code=200, message=result)
	},
	error = function(e) {
		cat("Error: getAllocations for protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error getting allocations")
	})
	return(allocations)
}
linkGasWallet = function(network, protocol, wallet, pool, apiKey) {
	response <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool); wallet <- tolower(wallet)
		cat("Linking Gas Wallet — network:", network, "protocol:", protocol, "pool:", pool, "\n")
		# apiKey is a UUID token from api_tokens; store directly, no re-encryption
		query <- "INSERT INTO gas_wallets (token, wallet_address, manager, network, protocol, pool, is_active)
		          VALUES (?, ?, '', ?, ?, ?, 1)
		          ON DUPLICATE KEY UPDATE token=VALUES(token), wallet_address=VALUES(wallet_address), is_active=1"
		dbExecute(con, query, params = list(apiKey, wallet, network, protocol, pool))
		list(status="success", status_code=200, message="Gas wallet successfully linked")
	},
	error = function(e) {
		cat("Error: linkGasWallet — protocol:", protocol, "network:", network, "wallet:", wallet, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error linking gas wallet")
	})
	return(response)
}
associateGasWallet = function(wallet, manager, label="default", apiKey) {
	wallet <- tolower(wallet); manager <- tolower(manager)
	response <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		cat("Associating Gas Wallet — manager:", manager, "wallet:", wallet, "\n")
		# apiKey is a UUID token; remove any existing association for this wallet under this manager
		dbExecute(con, "DELETE FROM gas_wallets WHERE manager = ? AND wallet_address = ? AND pool IS NULL",
		          params = list(manager, wallet))
		dbExecute(con, "INSERT INTO gas_wallets (token, wallet_address, manager, label, network, protocol, is_active) VALUES (?, ?, ?, ?, '', '', 1)",
		          params = list(apiKey, wallet, manager, label))
		list(status="success", status_code=200, message="Gas wallet successfully associated")
	},
	error = function(e) {
		cat("Error: associateGasWallet — manager:", manager, "wallet:", wallet, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error associating a gas wallet")
	})
	return(response)
}
deassociateGasWallet = function(wallet, manager) {
    wallet <- trimws(tolower(wallet))
    manager <- trimws(tolower(manager))
    response <- tryCatch({
        con <- db_con()
        on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
        dbExecute(con, "DELETE FROM gas_wallets WHERE wallet_address = ? AND manager = ? AND pool IS NULL",
                  params = list(wallet, manager))
        list(status="success", status_code=200, message="Gas wallet successfully deassociated")
    }, error = function(e) {
        cat("Error: deassociateGasWallet — wallet:", wallet, "manager:", manager, "error:", e$message, "\n")
        list(status="fail", status_code=500, message="Internal error deassociating gas wallet")
    })
    return(response)
}

getAssociatedGasWallets = function(manager, noKeys=FALSE) {
  gaswallets <- tryCatch({
    con = db_con()
    on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
    manager <- tolower(manager)
    if (noKeys) {
      res <- dbGetQuery(con, "SELECT wallet_address AS wallet, label FROM gas_wallets WHERE manager = ? AND pool IS NULL",
                        params = list(manager))
    } else {
      # Token is the API key — returned directly, no decryption needed
      res <- dbGetQuery(con, "SELECT wallet_address AS wallet, label, token AS apiKey FROM gas_wallets WHERE manager = ? AND pool IS NULL",
                        params = list(manager))
    }
    res
  }, error = function(e) {
    cat("Error: getAssociatedGasWallets — manager:", manager, "error:", e$message, "\n")
    list(status = "fail", status_code = 500, message = "Internal error listing associated gas wallets")
  })
  return(gaswallets)
}

getBots <- function(manager, protocol = "dhedge", filterNetwork = NULL) {
  result <- tryCatch({
    con <- db_con()
    on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
    manager <- tolower(manager)

    # Get all wallet addresses associated with this manager
    assoc <- dbGetQuery(con, "SELECT wallet_address AS wallet FROM gas_wallets WHERE manager = ? AND pool IS NULL",
                        params = list(manager))
    if (!is.data.frame(assoc) || nrow(assoc) == 0) {
      return(list(status = "success", status_code = 200, bots = list()))
    }

    # Single JOIN query: pool-linked gas wallets + their sides
    # filterNetwork: NULL / "all" = return all networks; specific chain = filter to that chain
    use_net_filter <- !is.null(filterNetwork) && nchar(filterNetwork) > 0 && tolower(filterNetwork) != "all"
    placeholders <- paste(rep("?", nrow(assoc)), collapse = ",")
    net_clause <- if (use_net_filter) " AND gw.network = ?" else ""
    query <- sprintf(
      "SELECT gw.network, gw.pool, gw.wallet_address AS gasWallet,
              ds.pair, ds.side, ds.threshold, ds.max_usd, ds.share, ds.platform, ds.slippage
       FROM gas_wallets gw
       LEFT JOIN dhedge_sides ds ON ds.pool = gw.pool AND ds.network = gw.network
       WHERE gw.protocol = ? AND gw.pool IS NOT NULL AND gw.wallet_address IN (%s)%s",
      placeholders, net_clause
    )
    params <- c(list(protocol), as.list(assoc$wallet))
    if (use_net_filter) params <- c(params, list(tolower(filterNetwork)))
    all_data <- dbGetQuery(con, query, params = params)

    bots <- list()
    if (nrow(all_data) > 0) {
      for (i in 1:nrow(all_data)) {
        row <- all_data[i, ]
        if (!is.na(row$pair)) {
          bots <- append(bots, list(list(
            pool = row$pool, gasWallet = row$gasWallet, network = row$network,
            pair = row$pair, side = row$side, threshold = row$threshold,
            max_usd = row$max_usd, share = row$share, platform = row$platform, slippage = row$slippage
          )))
        }
      }
    }
    list(status = "success", status_code = 200, bots = bots)
  }, error = function(e) {
    cat("Error: getBots — manager:", manager, "error:", e$message, "\n")
    list(status = "fail", status_code = 500, message = "Internal error fetching bots")
  })
  return(result)
}
#assc = getAssociatedGasWallets(manager="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5",noKey=TRUE)
#print(assc)
#print(assc$wallet[1])
#print(getBots(manager="0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5"))

listGasWallets = function(network, protocol) {
	gaswallets <- tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network)
		dbGetQuery(con, "SELECT wallet_address AS wallet FROM gas_wallets WHERE network = ? AND protocol = ? AND pool IS NOT NULL",
		           params = list(network, protocol))
	},
	error = function(e) {
		cat("Error: listGasWallets — protocol:", protocol, "network:", network, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error listing gas wallets")
	})
	return(gaswallets)
}

getPoolCredentials = function(network, protocol, pool) {
	poolCredentials <- tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		dbGetQuery(con, "SELECT id, token, wallet_address AS wallet, network, protocol, pool, is_active FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ?",
		           params = list(network, protocol, pool))
	},
	error = function(e) {
		cat("Error: getPoolCredentials — protocol:", protocol, "network:", network, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error getting pool credentials")
	})
	return(poolCredentials)
}

# Formerly listGasWalletsEncryptedKeys — now returns opaque UUID tokens (no ciphertext stored per-row)
listGasWalletTokens = function(network, protocol) {
	result <- tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network)
		res <- dbGetQuery(con, "SELECT token FROM gas_wallets WHERE network = ? AND protocol = ? AND pool IS NOT NULL",
		                  params = list(network, protocol))
		list(status="success", status_code=200, message=res)
	},
	error = function(e) {
		cat("Error: listGasWalletTokens — protocol:", protocol, "network:", network, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error listing gas wallet tokens")
	})
	return(result)
}

getRPC = function(network,protocol,pool) {
	rpc = c()
	rpc$provider="infura"
        rpc$provider_key = NULL
	tryCatch({
                table_name = paste0(network,"_",protocol,"_gas_wallets")
                con = db_con()
                query <- sprintf("SELECT provider,provider_key FROM %s WHERE pool = '%s'", table_name, pool)
                res <- dbGetQuery(con, query)
                dbDisconnect(con)
                if (nrow(res) > 0) {
			rpc$provider = res$provider[1]
			rpc$provider_key = res$provider_key[1]
		}
        },
        error = function(e) {
                print(paste0("Error fetching RPC provider for: ",network, " / ",protocol, " / ",pool," / providing default values"))
        })
        return(rpc)
}


getGasWallet = function(network, protocol, pool) {
	wallet = tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		res <- dbGetQuery(con, "SELECT wallet_address FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ?",
		                  params = list(network, protocol, pool))
		if (nrow(res) > 0) res$wallet_address[1] else NULL
	},
	error = function(e) {
		cat("Error: getGasWallet — network:", network, "protocol:", protocol, "pool:", pool, "error:", e$message, "\n")
		NULL
	})
	return(wallet)
}

getAPIKey = function(network, protocol, pool) {
	# Returns the UUID token for the gas wallet linked to this pool.
	# No decryption needed — the token IS the API key.
	apiKey = tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		res <- dbGetQuery(con, "SELECT token FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ?",
		                  params = list(network, protocol, pool))
		if (nrow(res) == 0) { cat("Error: No API key found for pool:", pool, "\n"); return(NULL) }
		res$token[1]
	},
	error = function(e) {
		cat("Error: getAPIKey — network:", network, "protocol:", protocol, "pool:", pool, "error:", e$message, "\n")
		NULL
	})
	return(apiKey)
}

isPoolActive = function(network, protocol, pool) {
	is_active = tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		res <- dbGetQuery(con, "SELECT is_active FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ?",
		                  params = list(network, protocol, pool))
		if (nrow(res) == 0) { cat("Error: pool not found:", pool, "\n"); return(FALSE) }
		res$is_active[1] == 1
	},
	error = function(e) {
		cat("Error: isPoolActive — network:", network, "protocol:", protocol, "pool:", pool, "error:", e$message, "\n")
		FALSE
	})
	return(is_active)
}
isValidApiKey = function(network, protocol, pool, apiKey) {
	tryCatch({
		con = db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		res <- dbGetQuery(con, "SELECT 1 FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ? AND token = ? LIMIT 1",
		                  params = list(tolower(network), protocol, tolower(pool), apiKey))
		nrow(res) > 0
	},
	error = function(e) {
		cat("Error: isValidApiKey:", e$message, "\n")
		FALSE
	})
}

deletePoolEverywhere <- function(network, protocol, pool, schema = NULL) {
  message(sprintf("Deleting references of pool %s on %s/%s", pool, network, protocol))

  con <- db_con()
  on.exit(dbDisconnect(con), add = TRUE)
  network <- tolower(network); pool <- tolower(pool)

  tryCatch({
    dbBegin(con)
    n_gw    <- DBI::dbExecute(con, "DELETE FROM gas_wallets WHERE pool = ? AND network = ? AND protocol = ?",
                              params = list(pool, network, protocol))
    n_sides <- DBI::dbExecute(con, "DELETE FROM dhedge_sides WHERE pool = ? AND network = ?",
                              params = list(pool, network))
    n_alloc <- DBI::dbExecute(con, "DELETE FROM dhedge_allocations WHERE pool = ? AND network = ?",
                              params = list(pool, network))
    dbCommit(con)
    deleted <- list(gas_wallets = n_gw, dhedge_sides = n_sides, dhedge_allocations = n_alloc)
    list(
      status = "success", status_code = 200, deleted = deleted,
      message = sprintf("Deleted pool %s: gas_wallets=%d, dhedge_sides=%d, dhedge_allocations=%d",
                        pool, n_gw, n_sides, n_alloc)
    )
  },
  error = function(e) {
    tryCatch(dbRollback(con), error = function(x) {})
    list(status = "fail", status_code = 500, message = sprintf("Error deleting pool: %s", e$message))
  })
}
unlinkGasWallet <- function(network, protocol, pool, schema = NULL) {
  message("unlinkGasWallet invoked")
  message(sprintf("network: %s / pool: %s / protocol: %s", network, pool, protocol))

  # Call the cross-table delete and forward its response structure as-is.
  # If an error is thrown anywhere inside, catch and return a fail payload.
  result <- tryCatch({
    res <- deletePoolEverywhere(network, protocol, pool, schema)

    # If deletePoolEverywhere already returns the API-style structure, just pass it through.
    # (status, status_code, message, deleted)
    if (is.list(res) &&
        !is.null(res$status) &&
        !is.null(res$status_code) &&
        !is.null(res$message)) {
      res
    } else {
      # Normalize unexpected shapes to a success with a sensible message.
      total_deleted <- tryCatch(sum(unlist(res$deleted)), error = function(...) NA_integer_)
      list(
        status      = "success",
        status_code = 200,
        message     = if (!is.na(total_deleted))
                        sprintf("Gas wallet unlinked and bots removed (total entries deleted: %d).", total_deleted)
                      else
                        "Gas wallet unlinked and bots removed."
      )
    }
  }, error = function(e) {
    list(
      status      = "fail",
      status_code = 500,
      message     = sprintf("Error unlinking gas wallet: %s", e$message)
    )
  })

  return(result)
}

#unlinkGasWallet <- function(network, protocol, pool, schema = NULL) {
#  message("unlinkGasWallet invoked")
#  message(sprintf("network: %s / pool: %s / protocol: %s", network, pool, protocol))
#
#  con <- db_con()
#  on.exit(dbDisconnect(con), add = TRUE)
#
#  table_name <- paste0(network, "_", protocol, "_gas_wallets")
#
#  # Quote the table identifier safely (optionally with schema)
#  tbl_id <- if (is.null(schema)) {
#    DBI::Id(table = table_name)
#  } else {
#    DBI::Id(schema = schema, table = table_name)
#  }
#  tbl <- DBI::dbQuoteIdentifier(con, tbl_id)
#
#  # Parameterized DELETE; returns number of rows affected
#  sql <- paste0("DELETE FROM ", tbl, " WHERE pool = ?")
#  n_deleted <- DBI::dbExecute(con, sql, params = list(pool))
#
#  list(
#    status       = "success",
#    status_code  = 200,
#    message      = if (n_deleted > 0)
#                     sprintf("Gas wallet unlinked (%d row%s).", n_deleted, ifelse(n_deleted==1,"","s"))
#                   else
#                     "No rows matched that pool (0 deleted)."
#  )
#}


getLinkedWallet <- function(network, protocol, pool) {
	response <- tryCatch({
		con <- db_con()
		on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add = TRUE)
		network <- tolower(network); pool <- tolower(pool)
		res <- dbGetQuery(con, "SELECT wallet_address FROM gas_wallets WHERE network = ? AND protocol = ? AND pool = ?",
		                  params = list(network, protocol, pool))
		if (nrow(res) > 0) res$wallet_address else character(0)
	},
	error = function(e) {
		cat("Error: getLinkedWallet — protocol:", protocol, "network:", network, "pool:", pool, "error:", e$message, "\n")
		list(status="fail", status_code=500, message="Internal error obtaining linked wallet")
	})
	return(response)
}

getUniV3Fee <- function(network, pair) {
	response <- tryCatch({
  		conn = db_con(); network = tolower(network); pair=toupper(pair)
  	  	network_id_query <- sprintf("SELECT network_id FROM networks WHERE name = '%s'", network)
  		network_id <- dbGetQuery(conn, network_id_query)$network_id
  		if (length(network_id) == 0) { fee_amount = 500 }
		else {
  			pair_id_query <- sprintf("SELECT pair_id FROM pairs WHERE network_id = %d AND pair = '%s'", network_id, pair)
        		pair_id <- dbGetQuery(conn, pair_id_query)$pair_id
        		if (length(pair_id) == 0) fee_amount = 500
			else {
        			fee_query <- sprintf("SELECT fee FROM uniV3Fees WHERE network_id = %d AND pair_id = %d", network_id, pair_id)
        			fee_amount <- dbGetQuery(conn, fee_query)$fee
        			if (length(fee_amount) == 0) fee_amount = 500
			}
		}
  		dbDisconnect(conn)
  		fee_amount
		},
		error = function(e) {
			cat("Error: retriving uniswapV3 fee (returning default 500) for network: ",network," pair: ",pair," error: ", e$message, "\n")
			fee_amount = 500
		})
	return(response)
}

getContract <- function(symbol, network) {
	response <- tryCatch({
		conn = db_con()
		symbol <- tolower(symbol); network <- tolower(network)
  		contract_query <- dbGetQuery(conn, "SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?", params = list(symbol, network))
  		if (nrow(contract_query) == 0) {
			cat("Warning: No contract found for the given symbol: ",symbol," and network: ",network," returning NULL\n")
			NULL
		}
		else { contract_query$contract }
  		},
		error = function(e) {
			cat("Error obtaining the contract for: ",symbol," and network: ",network," error: ",e$message," returning NULL\n")
			NULL
		})
	return(response)
}
#getContract("BTCBEAR1X","optimism")
getSymbol <- function(contract, network) {
	response <- tryCatch({
		conn = db_con()
  		contract <- tolower(contract); network <- tolower(network)
  		symbol_query <- dbGetQuery(conn, "SELECT c.symbol FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.contract = ? AND n.name = ?", params = list(contract, network))
 		if (nrow(symbol_query) == 0) {
			cat("No symbol found for the given contract:",contract," and network: ",network," returning NULL\n")
			NULL
		}
		else { symbol_query$symbol }
	},
	error = function(e) {
		cat("Error obtaining the symbol for: ",contract," and network: ",network," error: ",e$message," returning NULL\n")
                 NULL
	})
	return(response)
}

getCandles <- function(exchange, pair, timeframe, bars_back = 350) {
  con <- db_con()
  on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add=TRUE)
  table_name <- paste0("`", exchange, "_", pair, "_", timeframe, "`")

  # Modify query to fetch only the most recent bars_back candles
  bars_back <- as.integer(bars_back)
  if (is.na(bars_back) || bars_back <= 0) bars_back <- 350L
  query <- paste0("SELECT * FROM ", table_name, " ORDER BY time DESC LIMIT ", bars_back)

  # Execute the query and fetch data into a data frame
  OHLC <- tryCatch({
    dbGetQuery(con, query)
  }, error = function(e) {
    print(paste0("error fetching candles: ", e$message))
    NULL
  })

  if (!is.null(OHLC)) {
    # Convert Unix timestamp (assumed to be in the second column) to POSIXct and reverse the order
    OHLC[, 2] <- as.POSIXct(as.numeric(OHLC[, 2]), origin = "1970-01-01", tz = "UTC")

    # Reorder the data so it's ascending by time (oldest to newest)
    OHLC <- OHLC[order(OHLC$time), ]

    # Convert the rest of the columns as required
    OHLC <- cbind(OHLC[, 2], as.numeric(OHLC[, 3]), as.numeric(OHLC[, 4]),
                  as.numeric(OHLC[, 5]), as.numeric(OHLC[, 6]), as.numeric(OHLC[, 7]))

    OHLC <- as.data.frame(OHLC)
    colnames(OHLC) <- c("time", "low", "high", "open", "close", "volume")
  }
  return(OHLC)
}

#print(getCandles(exchange="coinbase",pair="BTC-USD",timeframe="6h",bars_back=10))

getTicks <- function(exchange,pair) {
	tick =
	tryCatch({
	tick = r$GET(paste0(exchange,"_",pair))
	}, error = function(e) {
		print(paste0("error :",e$message));
		NULL
	})
	if (!is.null(tick)) { return(as.numeric(tick)) }
	else { return(NULL) }
}

getTotalYield <- function(pool) {
	ty = r$GET(paste0(pool,"_totalYield"))
	if (is.null(ty)) return(list(status="fail",message="Invalid pool"))
	return(ty)
}

getAllYields <- function() {
	ty = list()
	for (pool in pools) {
        	total_yield <- r$GET(paste0(pool, "_totalYield"))
		APY <- r$GET(paste0(pool,"_APY"))
        	ty[[pool]] <- list(totalYield = total_yield,APY=APY)
    	}
        return(ty)
}
getEstimatedAnualYield <- function(pool) {
        APY = r$GET(paste0(pool,"_APY"))
        if (is.null(APY)) return(list(status="fail",message="Invalid pool"))
        return(APY)
}
getWalletPools <- function(protocol, network, wallet) {
  result <- tryCatch({
    con <- db_con()
    on.exit(tryCatch(dbDisconnect(con), error = function(e) {}), add=TRUE)

    networks <- if (tolower(network) == "all") c("optimism", "base", "arbitrum", "polygon") else tolower(network)
    placeholders <- paste(rep("?", length(networks)), collapse = ",")
    query <- sprintf(
      "SELECT network, pool, is_active FROM gas_wallets WHERE protocol = ? AND network IN (%s) AND wallet_address = ? AND pool IS NOT NULL",
      placeholders
    )
    params <- c(list(tolower(protocol)), as.list(networks), list(wallet))
    final_result <- dbGetQuery(con, query, params = params)
    rownames(final_result) <- NULL
    list(status = "success", status_code = 200, message = final_result)

  }, error = function(e) {
    cat("Error in getWalletPools:", e$message, "\n")
    list(status = "fail", status_code = 500, message = "Internal error getting pools for wallet")
  })
  return(result)
}
# getWalletPools(protocol = "dhedge", network = "all", wallet = "0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5")

#print(getTicks("coinbase","BTC-USD"))

##################
## Test scripts ##
##################

#delete_table("polygon_dhedge_sides")
#delete_table("dhedge_polygon_sides")

test = FALSE
if (test) {
	n = "polygon"; p = "dhedge"
	print("testing encryption")
	apiKey = "79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688"

	print("linking gas wallet"); print(linkGasWallet(network=n,protocol=p,wallet="mywallet",pool="myPool",apiKey=apiKey))

	print("is pool active?"); print(isPoolActive(network=n,protocol=p,pool="myPool"))

	print("obtaining pool credentials"); print(getPoolCredentials(network=n,protocol=p,pool="myPool"))

	print("listing gas wallets"); print(listGasWallets(network=n,protocol=p))

        print("listing gas wallets encrypted API Keys"); print(listGasWalletsEncryptedKeys(network=n,protocol=p))

	print("obtaining apiKey for myPool"); print(getAPIKey(network=n,protocol=p,pool="myPool"))

	print("is valid apiKey?:"); print(isValidApiKey(network=n,protocol=p,pool="myPool",apiKey=apiKey))

	print("setting allocations"); print(setAllocations(protocol=p,pool="myPool",network=n,assets="WBTC-WETH",allocations="50-50",upper_thresholds="10-10",lower_thresholds="10-10"))

	print("getting allocations"); print(getAllocations(protocol=p,pool="myPool",network=n))

	print("setting sides"); print(setSide(protocol=p,pool="myPool",network=n,pair="BTC-USD",side="neutral",slippage=1,threshold=1,max_usd=100,share=100,platform="uniswapV3"))

	print("getting side for a myPool"); print(getSide(protocol=p,pool="myPool",network=n))

	print("getting sides for all pools on dhedge and polygon"); print(getSides(protocol=p,network=n))

	print("getting sides from an empty network"); print(getSides(protocol=p,network="optimism"))

	print("obtaining linked wallet address from pool"); print(getLinkedWallet(network=n,protocol=p,pool="myPool"))

	print("unlinking gas wallet"); print(unlinkGasWallet(network=n,protocol=p,pool="myPool"))

	print("getting uniswapV3 fee for polygon and SNX-USDC"); print(getUniV3Fee(network="polygon",pair="SNX-USDC"))
	print("getting uniswapV3 fee for polygon and OP-USDC"); print(getUniV3Fee(network="polygon",pair="OP-USDC"))

	print("getting contract for WBTC on polygon"); contract = getContract(network="polygon",symbol="WBTC"); print(contract)
	print("getting symbol for WBTC contract on polygon"); print(getSymbol(network="polygon",contract=contract))
        print("getting contract for PEPE on polygon"); contract = getContract(network="polygon",symbol="PEPE"); print(contract)
        print("getting symbol for PEPE contract on polygon"); print(getSymbol(network="polygon",contract=contract))
}

#####################
## END OF API CODE ##
#####################

# Initialize cache on load (only if connection pool exists)
if (exists("db_pool", envir = .GlobalEnv)) {
  cache_init()
} else {
  cat("⚠️  Cache not initialized - waiting for connection pool\n")
}
