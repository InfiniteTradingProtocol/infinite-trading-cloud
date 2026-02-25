require(redux); require(DBI); require(httr); require(jsonlite); require(RMariaDB); require(dotenv); require(lubridate)
source("~/infinitetrading/src/api/getGasBalances.R")
source("~/infinitetrading/src/api/gasTracker.R")

load_dot_env("~/infinitetrading/src/api/.env")
#min gas balances
min_gas_usd=Sys.getenv("min_gas_usd")

sleep_seconds = 1.5

r <- redux::hiredis()

####################
# BASIC MYSQL CODE #
####################

db_connect = function(user,hostname,port,password,dbname){
        default_authentication_plugin=password
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname,host = hostname)
        return(con)
}

db_con = function() { db_connect(Sys.getenv("db_user"),Sys.getenv("db_ip"),Sys.getenv("db_port"),Sys.getenv("db_password"),dbname=Sys.getenv("db_schema")) }

gasMonitor <- function(network,protocol) {
    network = tolower(network); protocol=tolower(protocol)
    tryCatch({
        table_name <- paste0(network, "_", protocol, "_gas_wallets")
        con <- db_con()
        on.exit(dbDisconnect(con), add = TRUE)
        query <- sprintf("SELECT wallet FROM %s", table_name)
        res <- dbSendQuery(con, query)
        #on.exit(dbClearResult(res), add = TRUE)
	eth_price <- r$GET("coinbase_ETH-USD")
	matic_price <- r$GET("coinbase_POL-USD")
	print(paste0("ETH-USD price: ",eth_price))
	print(paste0("POL-USD price: ",matic_price))
	if (is.raw(eth_price)) eth_price <- rawToChar(eth_price)
	if (is.raw(matic_price)) matic_price <- rawToChar(matic_price)
	eth_price = as.numeric(eth_price)
	matic_price = as.numeric(matic_price)
	flag = 0
        repeat {
            wallets_batch <- dbFetch(res, n = max_batch_size)
            if (nrow(wallets_batch) == 0) break 
	    if (flag) { 
		    Sys.sleep(sleep_seconds);
	    	    #gasTracker(); # Disabled - Etherscan free tier removed
	    }
	    gasBalances = getGasBalances(wallets_batch$wallet,network=network)
            flag = 1
	    if (network == "base" || network == "mainnet" || network == "optimism") gasBalancesUSD = eth_price*gasBalances
	    else if (network == "polygon") gasBalancesUSD = matic_price*gasBalances
	    print(paste0("Gas wallets batch USD Balance: ", paste(gasBalancesUSD, collapse = ", ")))
	    counter = 1
	    for (balance in gasBalancesUSD) {
		if (balance < min_gas_usd) { 
			print(paste0("Gas wallet balance low: $",balance," / address: ",wallets_batch$wallet[counter]))
		}
	    	counter = counter + 1
	    }
        }
        dbClearResult(res)
	dbDisconnect(con)
    },
    error = function(e) { cat("An error occurred monitoring gas wallets for protocol: ", protocol, " network: ", network, " error: ", e$message, "\n") })
}

monitoring_hour = -1

repeat {
	#gasTracker(networks=c("optimism","arbitrum","polygon"))
	this_hour = hour(Sys.time())
	if (monitoring_hour != this_hour) { 
		gasMonitor(network="polygon",protocol="dhedge")
		#Sys.sleep(sleep_seconds)
		#gasTracker(networks=c("polygon","arbitrum","optimism"))
		#Sys.sleep(sleep_seconds)
		gasMonitor(network="optimism",protocol="dhedge")
    		#Sys.sleep(sleep_seconds)
		#gasTracker(networks=c("polygon","arbitrum","optimism"))
		#Sys.sleep(sleep_seconds)
		gasMonitor(network="arbitrum",protocol="dhedge")
		monitoring_hour = this_hour
		Sys.sleep(60*60)
    	}
	Sys.sleep(sleep_seconds)
}


