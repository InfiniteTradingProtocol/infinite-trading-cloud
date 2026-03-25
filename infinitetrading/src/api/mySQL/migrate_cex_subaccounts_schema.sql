-- Migration script to update cex_subaccounts table schema
-- Adds new columns for manager wallet and gas wallet tracking

ALTER TABLE cex_subaccounts 
ADD COLUMN manager_wallet VARCHAR(42) COMMENT 'Manager wallet address' AFTER id,
ADD COLUMN gas_wallet VARCHAR(42) COMMENT 'Gas wallet address (universal across all networks)' AFTER manager_wallet,
ADD COLUMN encrypted_gas_wallet_api_key TEXT COMMENT 'Encrypted ITP gas wallet API key' AFTER gas_wallet,
ADD COLUMN payment_network VARCHAR(20) NOT NULL DEFAULT 'base' COMMENT 'Network to charge fees from: ethereum, polygon, optimism, arbitrum, base' AFTER encrypted_gas_wallet_api_key,
ADD COLUMN gas_balance_usd DECIMAL(18,2) DEFAULT 0.00 COMMENT 'Cached total gas balance across all networks in USD' AFTER payment_network,
ADD COLUMN last_gas_check TIMESTAMP NULL COMMENT 'When gas balance was last checked' AFTER gas_balance_usd,
ADD COLUMN is_active BOOLEAN DEFAULT TRUE COMMENT 'Whether this subaccount is active' AFTER settings,
ADD INDEX idx_manager (manager_wallet),
ADD INDEX idx_gas_wallet (gas_wallet),
ADD INDEX idx_payment_network (payment_network),
ADD INDEX idx_active (is_active),
DROP INDEX unique_api_key_subaccount,
ADD UNIQUE KEY unique_manager_exchange_subaccount (manager_wallet, exchange, subaccount_name);

-- Add network column to cex_trades for fee tracking
ALTER TABLE cex_trades
ADD COLUMN fee_network VARCHAR(20) COMMENT 'Network fee was charged from' AFTER total_usd,
ADD COLUMN fee_amount_usd DECIMAL(10,4) DEFAULT 0.10 COMMENT 'Fee charged in USD' AFTER fee_network,
ADD COLUMN fee_tx_hash VARCHAR(66) COMMENT 'Transaction hash of fee payment' AFTER fee_amount_usd,
ADD INDEX idx_fee_network (fee_network);

-- Remove the old api_key column if no longer needed
-- ALTER TABLE cex_subaccounts DROP COLUMN api_key;

-- Update the comment
ALTER TABLE cex_subaccounts COMMENT = 'CEX trading subaccounts with multi-network gas wallet support and per-network fee charging';
ALTER TABLE cex_trades COMMENT = 'CEX trade execution records with network-specific fee tracking';
