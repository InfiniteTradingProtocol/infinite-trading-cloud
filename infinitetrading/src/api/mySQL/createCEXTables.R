##############################################
# Create CEX Trading Tables
# Handles DB connection and table creation
##############################################

require(dotenv); require(RMariaDB); require(DBI)
load_dot_env("~/infinitetrading/src/api/.env")

db_connect = function(user, hostname, port, password, dbname) {
    default_authentication_plugin = password
    con = dbConnect(RMariaDB::MariaDB(), user = user, password = password, dbname = dbname, hostname = hostname)
    return(con)
}

db_con = function() {
    con = db_connect(Sys.getenv("db_user"), Sys.getenv("db_ip"), Sys.getenv("db_port"), Sys.getenv("db_password"), dbname = Sys.getenv("db_schema"))
    return(con)
}

conn = db_con()

# Table: cex_strategies
# Stores strategy definitions for automated trading
sql_cex_strategies <- "
CREATE TABLE IF NOT EXISTS cex_strategies (
    id INT AUTO_INCREMENT PRIMARY KEY,
    strategy_name VARCHAR(100) UNIQUE NOT NULL COMMENT 'Strategy name: crossover, ema-rsi, etc',
    description TEXT COMMENT 'Strategy description',
    is_active BOOLEAN DEFAULT TRUE COMMENT 'Whether this strategy is available',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_strategy_name (strategy_name),
    INDEX idx_active (is_active)
);"

# Table: cex_subaccounts
# Stores CEX subaccount metadata (credentials encrypted and stored separately)
sql_cex_subaccounts <- "
CREATE TABLE IF NOT EXISTS cex_subaccounts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    api_key VARCHAR(128) NOT NULL COMMENT 'ITP API key (links to gas_wallets in RDS)',
    exchange VARCHAR(50) NOT NULL COMMENT 'Exchange name: coinbase, binance, okx, etc',
    subaccount_name VARCHAR(100) NOT NULL COMMENT 'User-friendly name for this subaccount',
    cex_api_key_encrypted TEXT NOT NULL COMMENT 'Encrypted CEX API key',
    cex_secret_encrypted TEXT NOT NULL COMMENT 'Encrypted CEX secret',
    cex_passphrase_encrypted TEXT COMMENT 'Encrypted CEX passphrase (for exchanges that need it)',
    settings JSON COMMENT 'Additional settings like testnet:true, subaccount, etc',
    total_balance_usd DECIMAL(18,2) DEFAULT 0.00 COMMENT 'Cached total balance in USD',
    last_balance_check TIMESTAMP NULL COMMENT 'When balance was last checked',
    last_balance_update TIMESTAMP NULL COMMENT 'When balance was last updated',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_api_key (api_key),
    INDEX idx_exchange (exchange),
    INDEX idx_balance_check (last_balance_check),
    UNIQUE KEY unique_api_key_subaccount (api_key, subaccount_name)
);"

# Table: cex_bots
# Stores bot trading configurations
sql_cex_bots <- "
CREATE TABLE IF NOT EXISTS cex_bots (
    id INT AUTO_INCREMENT PRIMARY KEY,
    subaccount_id INT NOT NULL COMMENT 'Foreign key to cex_subaccounts.id',
    strategy_id INT NULL COMMENT 'Foreign key to cex_strategies.id (NULL for custom)',
    pair VARCHAR(20) NOT NULL COMMENT 'Trading pair: BTC-USD, ETH-USDT, etc',
    side VARCHAR(10) DEFAULT 'hold' COMMENT 'Trading side: long, neutral, hold',
    previous_side VARCHAR(10) COMMENT 'Previous side to detect changes',
    max_usd DECIMAL(10,2) DEFAULT 100.00 COMMENT 'Maximum USD to use for this bot',
    share DECIMAL(5,2) DEFAULT 100.00 COMMENT 'Percentage of balance to use (0-100)',
    is_active BOOLEAN DEFAULT TRUE COMMENT 'Whether this bot is active',
    last_trade_at TIMESTAMP NULL COMMENT 'When the last trade was executed',
    last_side_change TIMESTAMP NULL COMMENT 'When side was last changed',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (subaccount_id) REFERENCES cex_subaccounts(id) ON DELETE CASCADE,
    FOREIGN KEY (strategy_id) REFERENCES cex_strategies(id) ON DELETE SET NULL,
    INDEX idx_subaccount_active (subaccount_id, is_active),
    INDEX idx_strategy (strategy_id),
    INDEX idx_pair (pair),
    INDEX idx_side (side),
    UNIQUE KEY unique_subaccount_pair (subaccount_id, pair)
);"

# Table: cex_trades
# Logs all trade executions
sql_cex_trades <- "
CREATE TABLE IF NOT EXISTS cex_trades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    subaccount_id INT NOT NULL COMMENT 'Foreign key to cex_subaccounts.id',
    bot_id INT COMMENT 'Foreign key to cex_bots.id (if applicable)',
    exchange_order_id VARCHAR(100) COMMENT 'Order ID from the exchange',
    pair VARCHAR(20) NOT NULL COMMENT 'Trading pair: BTC-USD, ETH-USDT, etc',
    side VARCHAR(10) NOT NULL COMMENT 'Trade side: buy, sell',
    quantity DECIMAL(20,8) COMMENT 'Amount of base currency traded',
    price DECIMAL(20,8) COMMENT 'Price per unit',
    total_usd DECIMAL(18,2) COMMENT 'Total value in USD',
    status VARCHAR(20) DEFAULT 'pending' COMMENT 'Order status: pending, filled, failed, cancelled',
    error_message TEXT COMMENT 'Error message if trade failed',
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (subaccount_id) REFERENCES cex_subaccounts(id) ON DELETE CASCADE,
    FOREIGN KEY (bot_id) REFERENCES cex_bots(id) ON DELETE SET NULL,
    INDEX idx_subaccount_trades (subaccount_id, executed_at),
    INDEX idx_bot_trades (bot_id, executed_at),
    INDEX idx_pair_trades (pair, executed_at),
    INDEX idx_status (status),
    INDEX idx_executed_at (executed_at)
);"

create_table <- function(query, conn = NULL) {
    tryCatch({
        if (is.null(conn)) { conn = db_con() }
        res = dbExecute(conn, query)
        print(res)
        message("Table created successfully or already exists.")
    }, error = function(e) {
        message("Error creating table: ", e$message)
    })
}

cat("Creating CEX trading tables...\n")

queries = c(
    sql_cex_strategies,
    sql_cex_subaccounts,
    sql_cex_bots,
    sql_cex_trades
)

for (query in queries) { 
    create_table(query, conn) 
}

dbDisconnect(conn)

cat("✅ CEX tables created successfully!\n")
