
# Dynamic path detection - works in both PM2 and direct execution
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    script_dir = dirname(normalizePath(ofile))
    wd = paste0(script_dir, "/")
  } else {
    script_dir = normalizePath(".")
    wd = paste0(script_dir, "/")
  }
}
cat("DEBUG: wd after initial detection:", wd, "\n")
publicSleepInterval = 0.1
require(DBI); require(RMariaDB); require(dotenv)
suppressPackageStartupMessages(require(slackr))  # Pre-load to avoid repeated require() calls in slack.R

load_dot_env(paste0(wd, ".env"))

# Load connection pool only if not disabled
disable_pool <- tolower(Sys.getenv("DISABLE_DB_POOL", "false")) == "true"
if (!disable_pool) {
  pool_path = paste0(wd, "db_pool.R")
  if (file.exists(pool_path)) {
    source(pool_path)
    cat("[POOL] Loaded connection pool from db_pool.R\n")
  } else {
    cat("[WARN] db_pool.R not found, using direct connections\n")
  }
} else {
  cat("[NO POOL] models.R skipping connection pool (DISABLE_DB_POOL=true)\n")
}

db_user = Sys.getenv("db_user")
db_password = Sys.getenv("db_password")

db_connect = function(user,hostname,port,password,dbname,rmysql=FALSE) {
        default_authentication_plugin=password
        con = dbConnect(RMariaDB::MariaDB(),user = user, password = password, dbname = dbname, host = hostname, port = port)
        return(con)
}
db_con = function(db=NULL, use_pool=TRUE) {
        if (is.null(db)) { db=Sys.getenv("db_schema") }
        
        # Try to use pool if available and requested
        if (use_pool && exists("db_pool", envir = .GlobalEnv)) {
                return(db_pool)
        }
        
        # Fallback to direct connection
        db_host_env = Sys.getenv("db_ip")
        if (db_host_env == "") db_host_env = Sys.getenv("db_host")
        if (db_host_env == "") db_host_env = "3.135.99.211"
        db_credentials = c(); db_credentials$user = db_user; db_credentials$ip = db_host_env; db_credentials$password = db_password; db_credentials$port = 3306
        con = db_connect(db_credentials$user,db_credentials$ip,db_credentials$port,db_credentials$password,dbname=db)
        return(con)
}

#source("/home/ubuntu/infinitetrading/db/candles_mysql.R")

# Define HL function directly to avoid quantmod loading issues
HL = function(OHLC) { return(cbind(OHLC[,3],OHLC[,2])) }
HLC = function(OHLC) { return(cbind(OHLC[,1],OHLC[,3],OHLC[,2],OHLC[,5])) }

# Source required files
if (file.exists(paste0(wd,"signals.R"))) source(paste0(wd,"signals.R"))
if (file.exists(paste0(wd,"slack.R"))) source(paste0(wd,"slack.R"))
if (file.exists(paste0(wd,"db.R"))) source(paste0(wd,"db.R"))

# Define reference function for compatibility
reference = function(package) {
  for (i in 1:length(package)) { 
    file_path = paste0(wd, package[i])
    if (file.exists(file_path)) source(file_path)
  }
}

# Try to load ML indicators if they exist
reference(c("ml/ml_indicators.R","ml/ml_indicators_hades.R"))

# Discord notification function (simple version if not loaded from slack.R)
if (!exists("discord")) {
  discord = function(msg, channel="#error-logs", db=TRUE) {
    cat(paste0("[", Sys.time(), "] ", channel, ": ", msg, "\n"))
  }
}

# Commented out to avoid DB lock issues during initialization
# discord(msg="Models thread initializing...",channel="#error-logs")
require(reticulate); require(quantmod); require(TTR); require(httr); require(rgdax); require(jsonlite); require(lubridate); require(snakecase); require(stringr)

predict_buy_probability = function(model,OHLC,n=2) {
	ind_matrix= ml_indicators(candles = OHLC, indicators = model$indicators,indicators_periods = model$indicators_periods,ind_rep =model$ind_rep) 
	features_vector = as.matrix(ind_matrix[-(1:6)])
	
	# Try keras3 3D input first, fall back to 2D for old keras
	pred_result = tryCatch({
		# Try 3D reshape for keras3
		n_samples = nrow(features_vector)
		n_features = ncol(features_vector)
		features_3d = array_reshape(features_vector, c(n_samples, 1, n_features))
		predict(model$model, features_3d)
	}, error = function(e) {
		# Fall back to 2D for old keras
		predict(model$model, features_vector)
	})
	
	# Extract probabilities based on output shape
	if (length(dim(pred_result)) == 3) {
		# 3D output: (samples, timesteps, classes) - take last timestep
		buy_probability = as.vector(pred_result[,dim(pred_result)[2],2])
	} else if (length(dim(pred_result)) == 2) {
		# 2D output: (samples, classes)
		buy_probability = as.vector(pred_result[,2])
	} else {
		# 1D or other - try to extract column 2
		buy_probability = as.vector(pred_result)
	}
	
	print(buy_probability)
        return(last(buy_probability,n))
}
predict_hades_buy_probability = function(model,OHLC,n=2) {
	print("calculating ml_indicator_matrix")
	ind_matrix = as.data.frame(ml_indicator_matrix(candles = OHLC, indicators = model$indicators,indicators_periods = model$indicators_periods,ind_rep =model$ind_rep))
	ind_matrix[is.na(ind_matrix)]=0
	ind_matrix %>% scale()
	print("predicting buy probability")
	prob1 = predict(model$model,as.matrix(ind_matrix))
	buy_probability = as.vector(prob1[,2])
	return(last(buy_probability,n))
}
load_models = function(models) {
        cat("DEBUG: wd inside load_models:", wd, "\n")
        
        # Load keras - try keras3 first, fall back to old keras
        if (!require(keras3, quietly = TRUE)) {
                require(keras)
                cat("DEBUG: Using old keras package\n")
        } else {
                cat("DEBUG: Using keras3 package\n")
        }
        
        require(tensorflow); require(TTR); require(quantmod);
	require(reticulate)
	# Use the r-tensorflow virtualenv
	use_virtualenv("~/.virtualenvs/r-tensorflow", required = FALSE)
	for (i in 1:length(models)) {
                model = paste(models[i],".hdf5",sep="")
                cat("Loading model: ",model,"\n")
                model_path = normalizePath(paste0(wd,"models/",model), mustWork = FALSE)
                cat("DEBUG: Full model path:", model_path, "\n")
                
                # Version-compatible model loading: try keras3 first, fall back to old keras
                keras_object = tryCatch({
                        load_model(model_path, custom_objects = NULL, compile = TRUE)
                }, error = function(e) {
                        # Fall back to old keras function (keras 2.x)
                        cat("DEBUG: First load_model failed, trying load_model_hdf5 (old keras)\n")
                        if (exists("load_model_hdf5")) {
                                load_model_hdf5(model_path, custom_objects = NULL, compile = TRUE)
                        } else {
                                cat("ERROR: Both load_model and load_model_hdf5 failed for", model, "\n")
                                cat("ERROR:", e$message, "\n")
                                return(NULL)
                        }
                })
                
                # Skip this model if loading failed
                if (is.null(keras_object)) {
                        cat("SKIPPING model:", model, "- failed to load\n")
                        next
                }
                
                model_object = c()
                rds_path = normalizePath(paste0(wd,"models/",models[i],".rds"), mustWork = FALSE)
                model_object = readRDS(file = rds_path)
                model_object$model = keras_object
                assign(models[i],model_object, envir = .GlobalEnv)
        }
}
models=c(
	 "ZeusBTC_6h-BTC-USD"
	 #"ZeusBTC_6h-ETH-USD",
	 #"ZeusBTC_6h-VELO-USD",
	 #"ZeusBTC_6h-ETH-USD-C-0.50-0.50",
	 #"ZeusBTC_6h-LINK-USD-C-0.30-0.70",
	 #"ZeusBTC_6h-OP-USD-CBE-0.30-0.30-0.30",
	 #"ZeusBTC_6h-ARB-USD-CBE-0.333-0.333-0.333",
	 #"ZeusBTC_6h-MATIC-USD-CBE-0.30-0.30-0.30",
	 #"ZeusBTC_6h-LINK-USD-CBE-0.30-0.30-0.30",
	 #"ZeusBTC_6h-SOL-USD-CBE-0.50-0.30-0.20",
	 #"SuperMACD_1d-MATIC-USD",
	 #"SuperMACD_1d-ETH-USD",
	 #"SuperMACD_1d-BTC-USD",
	 #"MomentumBTC_6h-BTC-USD-S",
	 #"AphroditeBTC_1h-BTC-USD-HA", "AphroditeBTC_1h-ARB-USD-HA",
	 #"ZeusBTC_6h-ARB-USD","HeraBTC_1d-ARB-USD-HA",
	 #"ZeusBTC_6h-BTC-USD-HA",
	 #"ZeusBTC_6h-ARB-USD-HA",
	 #"ZeusBTC_6h-ETH-USD-HA",
	 #"ZeusBTC_1d-BTC-USD","HeraBTC6h_1h-SOL-USD","HeraBTC6h_1h-BTC-USD",	 
	 #"HeraBTC_1d-OP-USD","HeraBTC_1d-BTC-USD",
	 #"HeraBTC_1d-ETH-USD",
	 #"HeraBTC_1d-MATIC-USD", "HeraBTC_6h-ETH-USD",
	 #"HeraBTC_1d-LINK-USD","HeraBTC_1d-LTC-USD",
	 #"HeraBTC_1d-SNX-USD","HeraBTC_1d-GRT-USD","HeraBTC_1d-CRV-USD","HeraBTC_1d-UNI-USD","HeraBTC_1d-SOL-USD","HeraBTC_1d-AAVE-USD","HeraBTC_1d-CRV-USD",
  	 
	 #"HeraBTC_15m-MATIC-USD","HeraBTC_15m-LINK-USD","HeraBTC_15m-ETH-USD","HeraBTC_15m-BTC-USD",
	 
	 #"HeraBTC_1h-LINK-USD","HeraBTC_1h-DOT-USD","HadesBTC_1h-BTC-USD","HeraBTC_1h-BTC-USD","HeraBTC_1h-ETH-USD",
	 #"HeraBTC_1h-MATIC-USD","HeraBTC_1h-DOGE-USD","HeraBTC_1h-LTC-USD","HeraBTC_1h-ADA-USD","HeraBTC_1h-SOL-USD","HeraBTC_1h-CRV-USD",

         #"HeraBTC_6h-GRT-USD","HeraBTC_6h-LDO-USD","HeraBTC_6h-ATOM-USD","HeraBTC_6h-OP-USD","HeraBTC_6h-ORN-USD","HeraBTC_6h-UNI-USD", "HeraBTC_6h-SNX-USD",
	 #"HeraBTC_6h-BTC-USD","HeraBTC_6h-ETH-USD","HeraBTC_6h-MATIC-USD","HeraBTC_6h-AAVE-USD","HeraBTC_6h-DOGE-USD",
	 #"HeraBTC_6h-LINK-USD","HeraBTC_6h-LTC-USD","HeraBTC_6h-ADA-USD","HeraBTC_6h-SOL-USD","HeraBTC_6h-CRV-USD",
	 
	 #"ZeusBTC_6h-SNX-USD",
	 #"LinkGPT_1h-LINK-USD",
	 #"ZeusBTC_6h-MATIC-USD","ZeusBTC_6h-OP-USD"#,"ZeusBTC_6h-LINK-USD"
)
models_to_load = c(); n = length(models)
for (i in 1:n) { 
	s = models[i]; s = strsplit(s, split = "-")[[1]]
	if (!any(models_to_load == s[1]) && s[1] != "SuperMACD_1d") { models_to_load = c(models_to_load,s[1]) }
}
# Local MySQL connection for candles (ephemeral data)
local_candles_con <- function() {
  db_user_local <- Sys.getenv("db_user_local")
  db_password_local <- Sys.getenv("db_password_local")
  if (db_user_local == "" || db_password_local == "") {
    stop("Missing db_user_local or db_password_local environment variables")
  }
  con <- dbConnect(RMariaDB::MariaDB(), user = db_user_local, password = db_password_local, dbname = "infinitetrading", host = "127.0.0.1", port = 3306)
  return(con)
}

get_candles_from_mysql <- function(pair, timeframe) {
  con = local_candles_con()
  table_name <- paste0("`coinbase_",pair, "_", timeframe,"`")
  # Assuming the column name for the timestamp is 'time'
  query <- paste0("SELECT * FROM ", table_name, " ORDER BY `time` ASC")
  # Execute the query and fetch data into a data frame
  OHLC = tryCatch({
          dbGetQuery(con, query)
  },error = function(e){ print(paste0("error fetching candles: ",e$message)); NULL })
  OHLC = cbind(as.POSIXct(as.numeric(OHLC[, 'time']), origin = "1970-01-01", tz = "UTC"),as.numeric(OHLC[,'low']),as.numeric(OHLC[,'high']),as.numeric(OHLC[,'open']),as.numeric(OHLC[,'close']),as.numeric(OHLC[,'volume']))
  OHLC <- as.data.frame(OHLC)
  colnames(OHLC) = c("time","low","high","open","close","volume")
  dbDisconnect(con)
  return(OHLC)
}

# Test
#print(get_candles_from_mysql(pair="BTC-USD",timeframe="6h"))
#return(0)

load_models(models_to_load)
last_report_hour = -1; info = matrix(nrow=n,ncol=5); colnames(info) = c("Model","Candles","Old Prob","Probability","Price"); rownames(info) = 1:n; index = 1

# Main loop with automatic recovery
while (1) {
	tryCatch({
		# Inner loop for processing models
		while (1) {
			this_hour = hour(Sys.time())
			pairtimeframe = c()
			for (i in 1:n) {
				combined=FALSE; combined_BE = FALSE;
				s = models[i]; s = strsplit(s, split = "-")[[1]]
				model = s[1]; s2 = strsplit(model, split = "_")[[1]]
				timeframe = s2[2]
				if (str_detect(tolower(models[i]),"supermacd")) { model = "SuperMACD" }
				else { model = get(model) }
				pair1 = s[2]; pair2 = s[3]

				if (!is.na(s[4])) { 
					if (s[4] == "HA") { heikin_ashi = TRUE; smoothed = FALSE }
					else if (s[4] == "S") { smoothed = TRUE; heikin_ashi = FALSE }
					else if (s[4] == "C") { combined=TRUE }
					else if (s[4] == "CBE") { combined_BE = TRUE }
				}
				else { heikin_ashi = FALSE; smoothed = FALSE }
				pair = paste(pair1,pair2,sep="-")
				print(models[i])
				name = paste(pair1,pair2,timeframe,sep="_")
				print(paste0("fetching candles for:",pair,"-",timeframe))
				#OHLC = pull_data(pair,timeframe,exchange="coinbase",training_size=600)
				OHLC = get_candles_from_mysql(pair=pair,timeframe=timeframe)
				if (nrow(OHLC) == 0) { 
					print(paste0("error; no candles found, skipping this pair and timeframe:",pair,timeframe))
					next
				}
				
				#if (any(pairtimeframe == name)) { OHLC = pull_candles(pair=pair,timeframe=timeframe,exchange="coinbase") }
				#else {
			 	#	OHLC = pull_data(pair,timeframe,exchange="coinbase",training_size=600)
				#	pairtimeframe = rbind(pairtimeframe,name)
				#	Sys.sleep(0.1)
				#}
				if (heikin_ashi) { source(paste0(wd,"/indicators/HeikinAshi.R")); OHLC = heikin_ashi(OHLC) }
				else if (smoothed) { 
					#Take the smoothing of the last 3 candles as the actual candle close/open/high/low and also the average volume
				        #SOHLC = as.data.frame(cbind(OHLC[,1],SMA(Lo(OHLC),3),SMA(Hi(OHLC),3),SMA(Op(OHLC),3),SMA(Cl(OHLC),3),SMA(Vo(OHLC),3)))
					#SOHLC = SOHLC[-(1:3),]
					#colnames(SOHLC) = names(OHLC);
					#OHLC = SOHLC
					#print(OHLC)
				}
				if (str_detect(tolower(models[i]),"hades")) { probabilities = predict_hades_buy_probability(model,OHLC); prob = last(probabilities); old_prob = first(last(probabilities,2)) }
				else if (str_detect(tolower(models[i]),"supermacd")) {
					SuperMACD = MACD(Cl(OHLC),nFast = 50,nSlow = 200,nSig = 7)
					signals = SuperMACD[,1] - SuperMACD[,2]
					probabilities = ifelse(signals < 0,0,1)
					prob = last(probabilities)
					old_prob = first(last(probabilities,2))
				}
				else {  
					probabilities = predict_buy_probability(model=model,OHLC=OHLC)
					prob = last(probabilities)
					# Debug prints removed to prevent buffer issues
					# print(tail(OHLC))
					# print(OHLC)
					if (tolower(models[i]) == "zeusbtc_6h-btc-usd") { zeusbtcbuyprob = prob }
					else if (tolower(models[i]) == "zeusbtc_6h-eth-usd") { zeusethbuyprob = prob }
					if (combined && !is.null(s[5]) && !is.null(s[6])) { 
						prob = prob*as.numeric(s[5]) + zeusbtcbuyprob*as.numeric(s[6])
						prob = min(prob,1)
					}
				else if (combined_BE && !is.null(s[5]) && !is.null(s[6]) && !is.null(s[7])) {
					prob = prob*as.numeric(s[5]) + zeusbtcbuyprob*as.numeric(s[6]) + zeusethbuyprob*as.numeric(s[7])
                                prob = min(prob,1)
				}
				# Use second-to-last probability from first prediction (faster, no extra prediction needed)
				old_prob = first(last(probabilities,2))
			}
			last_close = last(Cl(OHLC))				# Re-enabled database writes with simple error handling
				write_result = tryCatch({
					write_probabilities(model = models[i],timeframe=timeframe,old_probability = old_prob,probability = prob,last_close = last_close)
					"OK"
				}, error = function(e) {
					paste("FAILED:", e$message)
				})
				cat("[DB] write_probabilities:", write_result, "\n")
				
				stop_result = tryCatch({
					write_stop_losses(pair=pair,timeframe=timeframe,ohlc=OHLC)
					"OK"
				}, error = function(e) {
					paste("FAILED:", e$message)
				})
				cat("[DB] write_stop_losses:", stop_result, "\n")
				
				#signals_from_probabilities(probabilities,models[i])
				# TEMPORARILY DISABLED: Testing if Slack messages cause crashes
				# if (this_hour > last_report_hour|| (this_hour == 0 && last_report_hour == 23) ) { 
				# 	n_row_info = nrow(info)
				# 	if (length(n_row_info) == 0) { n_row_info = 0 } 
				# 	if (index <= n_row_info) { 
				# 		info[index,1] = models[i]; info[index,2] = timeframe; info[index,3] = round(old_prob,2); info[index,4] = round(prob,2); info[index,5] = round(last_close,2)
				# 		if (sum(nchar(na.omit(info))) > 3500) { 
				# 			tryCatch({
				# 				slack_message(info[1:index,],channel="#models")
				# 			}, error = function(e) {
				# 				cat("[WARN] slack_message failed:", e$message, "\n")
				# 			})
				# 			info = matrix(nrow=n,ncol=4);
				# 			colnames(info) = c("Model","Candles","Old Prob","Prob","Price")
				# 			rownames(info) = 1:n; index = 1
				# 			index = 1; 
				# 		}
				# 		else { index = index + 1 }
				# 	}
				# }
			}
			# TEMPORARILY DISABLED: Testing if Slack/database calls cause crashes
			# if (this_hour > last_report_hour || (this_hour == 0 && last_report_hour == 23) ) { 
			# 	info = na.omit(info)
			# 	
			# 	tryCatch({
			# 		stoplosses = read_stop_losses()
			# 		slack_message(stoplosses,channel="#stoploss_prices")
			# 	}, error = function(e) {
			# 		cat("[WARN] read_stop_losses or slack_message failed:", e$message, "\n")
			# 	})
			# 	
			# 	n_row_info = nrow(info)
			# 	if (length(n_row_info) > 0) { 
			# 		if (n_row_info > 0) {
			# 			tryCatch({
			# 				slack_message(info,channel="#models")
			# 			}, error = function(e) {
			# 				cat("[WARN] slack_message for models failed:", e$message, "\n")
			# 			})
			# 		}
			# 	} 
			# 	info = c(); last_report_hour = this_hour
			# }
			cat("[INFO] Completed processing cycle, sleeping 10s...\n")
			flush.console()  # Force output to be written immediately
			tryCatch({
				Sys.sleep(10)
			}, error = function(e) {
				cat("[WARN] Sys.sleep interrupted:", e$message, "\n")
			}, interrupt = function(e) {
				cat("[WARN] Sys.sleep got interrupt signal\n")
			})
		}
	}, error = function(e) {
		# Log the error but don't exit
		cat("[ERROR]", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "- Thread crashed:", e$message, "\n")
		tryCatch({
			discord(msg=paste0("ML Models thread crashed: ", e$message, " - Restarting in 30s..."), channel="#error-logs",db=FALSE)
		}, error = function(e2) {
			cat("[ERROR] Failed to send discord notification:", e2$message, "\n")
		})
		# Sleep before restarting the inner loop (avoids rapid crash loops)
		Sys.sleep(30)
		cat("[INFO] Restarting ML processing loop without reloading models...\n")
	})
}


