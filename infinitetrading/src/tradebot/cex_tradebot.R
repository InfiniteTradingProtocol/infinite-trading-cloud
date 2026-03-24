###############################
# CEX Automated Trading Bot  #
# - Iterates all subaccounts #
# - Checks balances          #
# - Auto-deactivates empty   #
# - Executes trades          #
###############################

source("~/infinitetrading/src/exchanges/cex_encryption_compact.R")
source("~/infinitetrading/src/db.R")
source("~/infinitetrading/src/slack.R")
require(reticulate)

# Initialize CCXT exchange object
init_ccxt_exchange <- function(credentials) {
    exchange_name <- credentials$exchange
    
    # Map exchange names to CCXT names
    ccxt_exchange <- exchange_name
    if (exchange_name == "coinbase") {
        ccxt_exchange <- "coinbaseexchange"  # Updated for 2024+
    }
    
    # Build initialization based on requirements
    if (exchange_name %in% c("coinbase", "okx", "kucoin", "bitget")) {
        # Needs passphrase
        if (is.null(credentials$passphrase)) {
            cat(sprintf("  ⚠️ Exchange %s requires passphrase but none provided\n", exchange_name))
            return(NULL)
        }
        py_string <- sprintf(
            "%s = ccxt.%s({
                'apiKey': '%s',
                'secret': '%s',
                'password': '%s',
                'enableRateLimit': True
            })",
            ccxt_exchange, ccxt_exchange,
            credentials$key,
            credentials$secret,
            credentials$passphrase
        )
    } else {
        # Standard (no passphrase)
        py_string <- sprintf(
            "%s = ccxt.%s({
                'apiKey': '%s',
                'secret': '%s',
                'enableRateLimit': True
            })",
            ccxt_exchange, ccxt_exchange,
            credentials$key,
            credentials$secret
        )
    }
    
    # Handle testnet
    if (!is.null(credentials$settings$testnet) && credentials$settings$testnet) {
        py_string <- paste0(py_string, sprintf("\n%s.set_sandbox_mode(True)", ccxt_exchange))
    }
    
    tryCatch({
        py_run_string(py_string)
        return(ccxt_exchange)
    }, error = function(e) {
        cat(sprintf("  ❌ Failed to initialize %s: %s\n", ccxt_exchange, e$message))
        return(NULL)
    })
}

# Get credentials from database
get_cex_credentials <- function(subaccount_id) {
    tryCatch({
        query <- sprintf(
            "SELECT 
                id, api_key, exchange, subaccount_name,
                cex_api_key_encrypted, cex_secret_encrypted, 
                cex_passphrase_encrypted, settings
             FROM cex_subaccounts
             WHERE id = %d",
            subaccount_id
        )
        
        result <- db_query(query)
        
        if (nrow(result) == 0) {
            return(NULL)
        }
        
        # Decrypt credentials
        decrypted_key <- decrypt_cex_credential(result$cex_api_key_encrypted[1])
        decrypted_secret <- decrypt_cex_credential(result$cex_secret_encrypted[1])
        decrypted_passphrase <- if (!is.na(result$cex_passphrase_encrypted[1]) && result$cex_passphrase_encrypted[1] != "") {
            decrypt_cex_credential(result$cex_passphrase_encrypted[1])
        } else {
            NULL
        }
        
        if (is.null(decrypted_key) || is.null(decrypted_secret)) {
            cat("  ❌ Failed to decrypt credentials\n")
            return(NULL)
        }
        
        # Parse settings
        settings <- if (!is.na(result$settings[1]) && result$settings[1] != "") {
            jsonlite::fromJSON(result$settings[1])
        } else {
            list()
        }
        
        return(list(
            subaccount_id = result$id[1],
            api_key = result$api_key[1],
            exchange = result$exchange[1],
            subaccount_name = result$subaccount_name[1],
            key = decrypted_key,
            secret = decrypted_secret,
            passphrase = decrypted_passphrase,
            settings = settings
        ))
        
    }, error = function(e) {
        cat(sprintf("  ❌ Error getting credentials: %s\n", e$message))
        return(NULL)
    })
}

# Check balance and auto-deactivate if below minimum
check_balance_and_deactivate <- function(exchange_obj, credentials, min_balance_usd = 1.0) {
    tryCatch({
        # Fetch balance
        py_string <- sprintf("balance = %s.fetchBalance()", exchange_obj)
        py_run_string(py_string)
        
        # Calculate total USD value
        py_run_string("
total_usd = 0.0
for currency in ['USD', 'USDC', 'USDT', 'DAI', 'BUSD']:
    if currency in balance and 'total' in balance[currency]:
        total_usd += float(balance[currency]['total'])
")
        
        total_usd <- py$total_usd
        
        # Update balance in database
        db_execute(sprintf(
            "UPDATE cex_subaccounts 
             SET total_balance_usd = %.2f, 
                 last_balance_check = NOW(), 
                 last_balance_update = NOW()
             WHERE id = %d",
            total_usd, credentials$subaccount_id
        ))
        
        # Check if balance is below minimum - DEACTIVATE BOTS ONLY (not subaccount)
        # User can still manually trade with low balance, but bots won't auto-trade
        if (total_usd < min_balance_usd) {
            cat(sprintf("  ⚠️ Balance below minimum: $%.2f < $%.2f - DEACTIVATING BOTS\n", 
                       total_usd, min_balance_usd))
            
            # Deactivate all bots for this subaccount (subaccount stays active)
            result <- db_execute(sprintf(
                "UPDATE cex_bots 
                 SET is_active = FALSE, 
                     updated_at = NOW()
                 WHERE subaccount_id = %d",
                credentials$subaccount_id
            ))
            
            # Send notification
            discord(sprintf(
                "⚠️ CEX Bots Deactivated (Low Balance) | Exchange: %s | Name: %s | Balance: $%.2f | Bots deactivated: %d",
                credentials$exchange, credentials$subaccount_name, total_usd, result
            ), channel = "#cex-alerts")
            
            return(list(active = FALSE, balance = total_usd))
        }
        
        cat(sprintf("  💰 Balance: $%.2f\n", total_usd))
        return(list(active = TRUE, balance = total_usd))
        
    }, error = function(e) {
        cat(sprintf("  ❌ Balance check failed: %s\n", e$message))
        return(list(active = TRUE, balance = NULL, error = e$message))
    })
}

# Execute trade based on bot configuration
execute_cex_trade <- function(exchange_obj, credentials, bot) {
    tryCatch({
        # Check if side changed (trigger immediate execution)
        side_changed <- is.na(bot$previous_side) || bot$previous_side != bot$side
        
        # Fetch current balance
        py_string <- sprintf("balance = %s.fetchBalance()", exchange_obj)
        py_run_string(py_string)
        
        # Parse pair (BTC-USD -> BTC/USD for CCXT)
        pair_ccxt <- gsub("-", "/", bot$pair)
        base_currency <- strsplit(bot$pair, "-")[[1]][1]
        quote_currency <- strsplit(bot$pair, "-")[[1]][2]
        
        # Get balances
        py_run_string(sprintf("
base_balance = float(balance.get('%s', {}).get('free', 0))
quote_balance = float(balance.get('%s', {}).get('free', 0))
", base_currency, quote_currency))
        
        base_balance <- py$base_balance
        quote_balance <- py$quote_balance
        
        cat(sprintf("  📊 %.8f %s | %.2f %s\n", 
                   base_balance, base_currency, quote_balance, quote_currency))
        
        # Determine action
        if (bot$side == "long") {
            # Should be in crypto - check if we need to buy
            if (quote_balance > 15 && (side_changed || quote_balance > bot$max_usd * 0.1)) {
                # Buy crypto with available quote currency
                execute_buy_order(exchange_obj, credentials, bot, pair_ccxt, quote_balance, base_currency)
            } else {
                cat("  ⏸️ Already long, no action needed\n")
            }
        } else if (bot$side == "neutral") {
            # Should be in quote currency - check if we need to sell
            if (base_balance > 0.0001 && side_changed) {  # Has crypto to sell
                # Sell all crypto to quote currency
                execute_sell_order(exchange_obj, credentials, bot, pair_ccxt, base_balance, base_currency)
            } else {
                cat("  ⏸️ Already neutral, no action needed\n")
            }
        }
        
        # Update previous_side to track changes
        if (side_changed) {
            db_execute(sprintf(
                "UPDATE cex_bots 
                 SET previous_side = '%s', updated_at = NOW()
                 WHERE id = %d",
                bot$side, bot$bot_id
            ))
        }
        
    }, error = function(e) {
        cat(sprintf("  ❌ Trade execution error: %s\n", e$message))
    })
}

# Execute buy order
execute_buy_order <- function(exchange_obj, credentials, bot, pair_ccxt, available_quote, base_currency) {
    tryCatch({
        # Calculate amount to spend
        amount_to_spend <- min(available_quote * (bot$share / 100), bot$max_usd)
        
        if (amount_to_spend < 15) {
            cat(sprintf("  ⚠️ Amount too small: $%.2f\n", amount_to_spend))
            return()
        }
        
        # Get current price
        py_string <- sprintf("ticker = %s.fetchTicker('%s')", exchange_obj, pair_ccxt)
        py_run_string(py_string)
        py_run_string("current_price = float(ticker['last'])")
        price <- py$current_price
        
        # Calculate quantity
        quantity <- amount_to_spend / price
        
        cat(sprintf("  🔵 BUY: %.8f %s @ $%.2f = $%.2f\n", 
                   quantity, base_currency, price, amount_to_spend))
        
        # Execute market buy order
        py_string <- sprintf(
            "order = %s.createMarketBuyOrder('%s', %.8f)",
            exchange_obj, pair_ccxt, quantity
        )
        py_run_string(py_string)
        
        # Log trade
        log_cex_trade(
            subaccount_id = credentials$subaccount_id,
            bot_id = bot$bot_id,
            pair = bot$pair,
            side = "buy",
            quantity = quantity,
            price = price,
            total_usd = amount_to_spend,
            order_id = if (!is.null(py$order$id)) py$order$id else NULL,
            status = "filled"
        )
        
        cat("  ✅ Buy order executed\n")
        
        # Notification
        discord(sprintf(
            "🔵 CEX BUY | %s/%s | %s | %.8f @ $%.2f = $%.2f",
            credentials$exchange, credentials$subaccount_name, bot$pair, quantity, price, amount_to_spend
        ), channel = "#cex-trades")
        
        # Update last trade time
        db_execute(sprintf(
            "UPDATE cex_bots SET last_trade_at = NOW() WHERE id = %d",
            bot$bot_id
        ))
        
    }, error = function(e) {
        cat(sprintf("  ❌ Buy order failed: %s\n", e$message))
        log_cex_trade(
            subaccount_id = credentials$subaccount_id,
            bot_id = bot$bot_id,
            pair = bot$pair,
            side = "buy",
            status = "failed",
            error_message = e$message
        )
    })
}

# Execute sell order
execute_sell_order <- function(exchange_obj, credentials, bot, pair_ccxt, available_base, base_currency) {
    tryCatch({
        # Calculate amount to sell
        quantity_to_sell <- available_base * (bot$share / 100)
        
        # Get current price
        py_string <- sprintf("ticker = %s.fetchTicker('%s')", exchange_obj, pair_ccxt)
        py_run_string(py_string)
        py_run_string("current_price = float(ticker['last'])")
        price <- py$current_price
        
        total_value <- quantity_to_sell * price
        
        if (total_value < 15) {
            cat(sprintf("  ⚠️ Sell value too small: $%.2f\n", total_value))
            return()
        }
        
        cat(sprintf("  🔴 SELL: %.8f %s @ $%.2f = $%.2f\n", 
                   quantity_to_sell, base_currency, price, total_value))
        
        # Execute market sell order
        py_string <- sprintf(
            "order = %s.createMarketSellOrder('%s', %.8f)",
            exchange_obj, pair_ccxt, quantity_to_sell
        )
        py_run_string(py_string)
        
        # Log trade
        log_cex_trade(
            subaccount_id = credentials$subaccount_id,
            bot_id = bot$bot_id,
            pair = bot$pair,
            side = "sell",
            quantity = quantity_to_sell,
            price = price,
            total_usd = total_value,
            order_id = if (!is.null(py$order$id)) py$order$id else NULL,
            status = "filled"
        )
        
        cat("  ✅ Sell order executed\n")
        
        # Notification
        discord(sprintf(
            "🔴 CEX SELL | %s/%s | %s | %.8f @ $%.2f = $%.2f",
            credentials$exchange, credentials$subaccount_name, bot$pair, quantity_to_sell, price, total_value
        ), channel = "#cex-trades")
        
        # Update last trade time
        db_execute(sprintf(
            "UPDATE cex_bots SET last_trade_at = NOW() WHERE id = %d",
            bot$bot_id
        ))
        
    }, error = function(e) {
        cat(sprintf("  ❌ Sell order failed: %s\n", e$message))
        log_cex_trade(
            subaccount_id = credentials$subaccount_id,
            bot_id = bot$bot_id,
            pair = bot$pair,
            side = "sell",
            status = "failed",
            error_message = e$message
        )
    })
}

# Log trade to database
log_cex_trade <- function(subaccount_id, bot_id, pair, side, quantity = NULL, price = NULL, 
                          total_usd = NULL, order_id = NULL, status = "pending", error_message = NULL) {
    query <- sprintf(
        "INSERT INTO cex_trades 
        (subaccount_id, bot_id, exchange_order_id, pair, side, quantity, price, total_usd, status, error_message)
        VALUES (%d, %s, %s, '%s', '%s', %s, %s, %s, '%s', %s)",
        subaccount_id,
        ifelse(is.null(bot_id), "NULL", bot_id),
        ifelse(is.null(order_id), "NULL", paste0("'", order_id, "'")),
        pair, side,
        ifelse(is.null(quantity), "NULL", quantity),
        ifelse(is.null(price), "NULL", price),
        ifelse(is.null(total_usd), "NULL", total_usd),
        status,
        ifelse(is.null(error_message), "NULL", paste0("'", gsub("'", "''", error_message), "'"))
    )
    db_execute(query)
}

# Main trading loop
cex_trading_bot <- function(min_balance_usd = 1.0, cycle_interval_sec = 60) {
    py_run_string("import ccxt")
    
    cat("═══════════════════════════════════════════\n")
    cat("    CEX Automated Trading Bot Started      \n")
    cat("═══════════════════════════════════════════\n\n")
    
    while (TRUE) {
        tryCatch({
            cat(sprintf("\n[%s] Starting bot cycle\n", 
                       format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
            
            # Get all subaccounts with active bots
            # Subaccounts either exist or are deleted - only check bot is_active
            query <- "
                SELECT DISTINCT
                    s.id as subaccount_id,
                    s.exchange,
                    s.subaccount_name,
                    s.total_balance_usd
                FROM cex_subaccounts s
                INNER JOIN cex_bots b ON s.id = b.subaccount_id
                WHERE b.is_active = TRUE
                  AND b.side != 'hold'
            "
            
            subaccounts <- db_query(query)
            
            if (nrow(subaccounts) == 0) {
                cat("No active subaccounts with active bots found\n")
                Sys.sleep(cycle_interval_sec)
                next
            }
            
            cat(sprintf("Processing %d active subaccount(s)\n", nrow(subaccounts)))
            
            # Process each subaccount
            for (i in 1:nrow(subaccounts)) {
                subaccount <- subaccounts[i,]
                
                tryCatch({
                    cat(sprintf("\n─── Subaccount %d/%d: %s/%s ───\n", 
                               i, nrow(subaccounts), subaccount$exchange, subaccount$subaccount_name))
                    
                    # Get credentials
                    credentials <- get_cex_credentials(subaccount$subaccount_id)
                    if (is.null(credentials)) {
                        cat("  ⚠️ Failed to get credentials\n")
                        next
                    }
                    
                    # Initialize exchange
                    exchange_obj <- init_ccxt_exchange(credentials)
                    if (is.null(exchange_obj)) {
                        next
                    }
                    
                    # Check balance and auto-deactivate if below minimum
                    balance_check <- check_balance_and_deactivate(
                        exchange_obj, 
                        credentials, 
                        min_balance_usd
                    )
                    
                    if (!balance_check$active) {
                        cat("  🚫 Bots deactivated due to low balance\n")
                        next  # Skip trading for this subaccount
                    }
                    
                    # Get active bots for this subaccount
                    bots_query <- sprintf(
                        "SELECT 
                            id as bot_id,
                            subaccount_id,
                            pair,
                            side,
                            previous_side,
                            max_usd,
                            share
                         FROM cex_bots
                         WHERE subaccount_id = %d 
                           AND is_active = TRUE
                           AND side != 'hold'
                           AND strategy_id IS NULL",  # Only custom bots (manual control)
                        subaccount$subaccount_id
                    )
                    
                    bots <- db_query(bots_query)
                    
                    if (nrow(bots) == 0) {
                        cat("  ⏸️ No active custom bots for this subaccount\n")
                    } else {
                        cat(sprintf("  🤖 Processing %d bot(s)\n", nrow(bots)))
                        
                        # Execute trades for each bot
                        for (j in 1:nrow(bots)) {
                            bot <- bots[j,]
                            cat(sprintf("    [Bot %d] %s - %s\n", j, bot$pair, bot$side))
                            
                            execute_cex_trade(exchange_obj, credentials, bot)
                            
                            Sys.sleep(0.3)  # Rate limit between bot trades
                        }
                    }
                    
                    Sys.sleep(0.5)  # Rate limit between subaccounts
                    
                }, error = function(e) {
                    cat(sprintf("  ❌ Subaccount error: %s\n", e$message))
                })
            }
            
            cat(sprintf("\n⏰ Cycle complete. Sleeping %d seconds...\n", cycle_interval_sec))
            cat("═══════════════════════════════════════════\n")
            
            Sys.sleep(cycle_interval_sec)
            
        }, error = function(e) {
            cat(sprintf("❌ Bot loop error: %s\n", e$message))
            discord(paste("CEX Bot Error:", e$message), channel = "#errors")
            Sys.sleep(cycle_interval_sec)
        })
    }
}

# Start the bot
if (!interactive()) {
    cex_trading_bot(min_balance_usd = 1.0, cycle_interval_sec = 60)
}
