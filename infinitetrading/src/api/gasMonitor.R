require(redux); require(DBI); require(httr); require(jsonlite); require(RMariaDB); require(dotenv); require(lubridate)
source("~/infinitetrading/src/api/getGasBalances.R")
source("~/infinitetrading/src/api/gasTracker.R")
source("~/infinitetrading/src/utils/email_alerts.R")

load_dot_env("~/infinitetrading/src/api/.env")
#min gas balances
min_gas_usd=Sys.getenv("min_gas_usd")
MASTER_WALLET <- Sys.getenv("MASTER_WALLET")
MIN_GAS_ETH   <- 0.002   # alert threshold: < 0.002 ETH on Base

# Alert state: max 2 gas-low emails per day
gas_alert <- new.env(parent = emptyenv())
gas_alert$count <- 0L
gas_alert$date  <- Sys.Date()

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

		# ── Master wallet gas check on Base ──────────────────────────────────
		if (nchar(MASTER_WALLET) > 0) {
		  tryCatch({
		    eth_bal <- get_balance_rpc(MASTER_WALLET, rpc_endpoints[["base"]])
		    cat(sprintf("[Gas Check] Master wallet Base ETH: %.6f\n", eth_bal))
		    if (!is.null(eth_bal) && !is.na(eth_bal) && eth_bal < MIN_GAS_ETH) {
		      if (can_send_alert(gas_alert)) {
		        send_resend_email(
		          subject   = sprintf("\u26fd\ufe0f Low Gas Warning - Base (%.6f ETH)", eth_bal),
		          html_body = sprintf(paste0(
		            "<h2>&#9981; Gas Wallet Low on Base</h2>",
		            "<p><strong>Wallet:</strong> %s</p>",
		            "<p><strong>Balance:</strong> %.6f ETH (threshold: %.3f ETH)</p>",
		            "<p>Please top up the gas wallet to keep strategies running.</p>",
		            "<p><em>%s UTC</em></p>"
		          ), MASTER_WALLET, eth_bal, MIN_GAS_ETH, format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
		        )
		        gas_alert$count <- gas_alert$count + 1L
		      }
		    }
		  }, error = function(e) {
		    cat(sprintf("[Gas Check] Error checking master wallet: %s\n", e$message))
		  })
		}

		monitoring_hour = this_hour
		Sys.sleep(60*60)
    	}
	Sys.sleep(sleep_seconds)
}


