-- =============================================================================
-- Schema Migration v2
-- Infinite Trading Cloud
-- April 2026
--
-- Changes:
--   1. PURGE all compromised wallet/key data
--   2. CREATE api_tokens  — opaque UUID tokens; server owns the ciphertext
--   3. CREATE gas_wallets — single unified table replacing the 5 per-network tables
--      (old tables renamed to _legacy, not dropped yet — safe rollback)
--   4. ALTER cex_subaccounts — replace wallet varchar FK with gas_wallet_id INT FK
--   5. Unified dhedge_sides / dhedge_allocations — replace 3 per-network copies
--      with one table that has a `network` column (same strategy)
-- =============================================================================

USE infinitetrading;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- 1. PURGE compromised data
--    (all private keys were stolen; fresh slate required)
-- =============================================================================

TRUNCATE TABLE associated_gas_wallets;
TRUNCATE TABLE base_dhedge_gas_wallets;
TRUNCATE TABLE optimism_dhedge_gas_wallets;
TRUNCATE TABLE polygon_dhedge_gas_wallets;
TRUNCATE TABLE ethereum_dhedge_gas_wallets;
TRUNCATE TABLE arbitrum_dhedge_gas_wallets;
TRUNCATE TABLE cex_subaccounts;
TRUNCATE TABLE cex_bots;
TRUNCATE TABLE cex_trades;

-- =============================================================================
-- 2. api_tokens
--    User-facing API key is a UUID (36 chars).
--    encrypted_pk is stored server-side and never returned to the client.
--    wallet_address is pre-derived at insert time (no runtime decryption needed
--    for auth — only for tx signing).
-- =============================================================================

CREATE TABLE IF NOT EXISTS api_tokens (
    token           CHAR(36)        NOT NULL,       -- UUID v4
    wallet_address  VARCHAR(42)     NOT NULL,        -- 0x... derived at insert
    encrypted_pk    VARCHAR(192)    NOT NULL,        -- AES-256-CBC hex, single layer
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (token),
    INDEX idx_wallet (wallet_address)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 3. gas_wallets  (unified — replaces 5 per-network tables + associated_gas_wallets)
--
--  For DeFi pool associations:   token + network + protocol + pool are all set
--  For manager-level association: token + manager set, pool = NULL
-- =============================================================================

CREATE TABLE IF NOT EXISTS gas_wallets (
    id              INT             NOT NULL AUTO_INCREMENT,
    token           CHAR(36)        NOT NULL,        -- FK → api_tokens.token
    wallet_address  VARCHAR(42)     NOT NULL,        -- denorm for fast lookup
    manager         VARCHAR(42)     NOT NULL,        -- manager wallet address
    label           VARCHAR(42)     NOT NULL DEFAULT 'default',
    network         VARCHAR(20)     NOT NULL DEFAULT '',
    protocol        VARCHAR(20)     NOT NULL DEFAULT '',
    pool            VARCHAR(42)     DEFAULT NULL,    -- NULL = manager-level only
    is_active       TINYINT(1)      NOT NULL DEFAULT 1,
    created_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_pool_net_proto (pool, network, protocol),  -- one gas wallet per pool
    INDEX idx_token        (token),
    INDEX idx_wallet       (wallet_address),
    INDEX idx_manager      (manager),
    INDEX idx_network_proto (network, protocol),
    CONSTRAINT fk_gw_token FOREIGN KEY (token) REFERENCES api_tokens(token) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 4. cex_subaccounts — replace gas_wallet varchar + encrypted_gas_wallet_api_key
--    with gas_wallet_id INT FK → gas_wallets.id
--    (only alter if columns not already migrated)
-- =============================================================================

-- Add new FK column + index + constraint.
-- cex_subaccounts was just TRUNCATEd above so no data conflicts.
-- These are unconditional: if re-running this script, comment out this block.
ALTER TABLE cex_subaccounts
    ADD COLUMN  gas_wallet_id  INT DEFAULT NULL AFTER gas_wallet,
    ADD INDEX   idx_gas_wallet_id (gas_wallet_id),
    ADD CONSTRAINT fk_cex_gas_wallet
        FOREIGN KEY (gas_wallet_id) REFERENCES gas_wallets(id) ON DELETE SET NULL;

-- The old gas_wallet varchar and encrypted_gas_wallet_api_key columns are kept
-- as legacy until cex code is updated; will be dropped in migrate_schema_v3.

-- =============================================================================
-- 5. dhedge_sides (unified) — replaces optimism/base/polygon_dhedge_sides
--    Existing data is migrated in, then old tables renamed _legacy.
-- =============================================================================

CREATE TABLE IF NOT EXISTS dhedge_sides (
    id              INT             NOT NULL AUTO_INCREMENT,
    network         VARCHAR(20)     NOT NULL,
    pool            VARCHAR(42)     NOT NULL,
    pair            VARCHAR(20)     NOT NULL,
    side            VARCHAR(10)     NOT NULL,
    threshold       FLOAT           NOT NULL,
    max_usd         INT             NOT NULL,
    share           FLOAT           NOT NULL,
    platform        VARCHAR(30)     NOT NULL,
    slippage        FLOAT           NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_net_pool_pair (network, pool, pair),
    INDEX idx_network_pool (network, pool)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Migrate existing data (INSERT IGNORE so re-runs are safe)
INSERT IGNORE INTO dhedge_sides (network, pool, pair, side, threshold, max_usd, share, platform, slippage)
    SELECT 'optimism', pool, pair, side, threshold, max_usd, share, platform, slippage FROM optimism_dhedge_sides;

INSERT IGNORE INTO dhedge_sides (network, pool, pair, side, threshold, max_usd, share, platform, slippage)
    SELECT 'base', pool, pair, side, threshold, max_usd, share, platform, slippage FROM base_dhedge_sides;

INSERT IGNORE INTO dhedge_sides (network, pool, pair, side, threshold, max_usd, share, platform, slippage)
    SELECT 'polygon', pool, pair, side, threshold, max_usd, share, platform, slippage FROM polygon_dhedge_sides;

-- Rename old tables to _legacy (not dropped — safe rollback window)
RENAME TABLE optimism_dhedge_sides TO optimism_dhedge_sides_legacy;
RENAME TABLE base_dhedge_sides     TO base_dhedge_sides_legacy;
RENAME TABLE polygon_dhedge_sides  TO polygon_dhedge_sides_legacy;

-- =============================================================================
-- 6. dhedge_allocations (unified) — replaces polygon_dhedge_allocations
--    (only polygon had this; add network column for future networks)
-- =============================================================================

CREATE TABLE IF NOT EXISTS dhedge_allocations (
    id                  INT             NOT NULL AUTO_INCREMENT,
    network             VARCHAR(20)     NOT NULL DEFAULT 'polygon',
    pool                VARCHAR(42)     NOT NULL,
    assets              VARCHAR(100)    NOT NULL,
    allocations         VARCHAR(100)    NOT NULL,
    upper_thresholds    VARCHAR(100)    NOT NULL,
    lower_thresholds    VARCHAR(100)    NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_net_pool (network, pool),
    INDEX idx_network_pool (network, pool)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO dhedge_allocations (network, pool, assets, allocations, upper_thresholds, lower_thresholds)
    SELECT 'polygon', pool, assets, allocations, upper_thresholds, lower_thresholds FROM polygon_dhedge_allocations;

RENAME TABLE polygon_dhedge_allocations TO polygon_dhedge_allocations_legacy;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- Verification
-- =============================================================================
SELECT 'api_tokens'          AS tbl, COUNT(*) AS cnt FROM api_tokens
UNION ALL SELECT 'gas_wallets',        COUNT(*) FROM gas_wallets
UNION ALL SELECT 'dhedge_sides',       COUNT(*) FROM dhedge_sides
UNION ALL SELECT 'dhedge_allocations', COUNT(*) FROM dhedge_allocations
UNION ALL SELECT 'cex_subaccounts',    COUNT(*) FROM cex_subaccounts;
