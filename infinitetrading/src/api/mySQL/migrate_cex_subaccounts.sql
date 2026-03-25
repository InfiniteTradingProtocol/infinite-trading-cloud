-- CEX Subaccounts Table Migration
-- Add new authentication columns and remove old api_key

USE infinitetrading;

-- Add new columns
ALTER TABLE cex_subaccounts
ADD COLUMN manager_wallet VARCHAR(42) AFTER id,
ADD COLUMN gas_wallet VARCHAR(42) AFTER manager_wallet,
ADD COLUMN encrypted_gas_wallet_api_key VARCHAR(256) AFTER gas_wallet,
ADD COLUMN is_active BOOLEAN DEFAULT TRUE AFTER cex_passphrase_encrypted,
ADD COLUMN gas_balance_usd DECIMAL(18,2) DEFAULT 0.00 AFTER is_active,
ADD COLUMN last_gas_check TIMESTAMP NULL AFTER last_balance_check;

-- Drop old api_key column and its indexes
ALTER TABLE cex_subaccounts
DROP INDEX unique_api_key_subaccount,
DROP INDEX idx_api_key,
DROP COLUMN api_key;

-- Add new indexes
ALTER TABLE cex_subaccounts
ADD INDEX idx_manager (manager_wallet),
ADD INDEX idx_gas_wallet (gas_wallet),
ADD INDEX idx_encrypted_key (encrypted_gas_wallet_api_key(255)),
ADD INDEX idx_active (is_active),
ADD INDEX idx_gas_check (last_gas_check);

-- Update unique constraint to use manager_wallet
ALTER TABLE cex_subaccounts
ADD UNIQUE KEY unique_subaccount (manager_wallet, exchange, subaccount_name);

-- Show final structure
DESCRIBE cex_subaccounts;
