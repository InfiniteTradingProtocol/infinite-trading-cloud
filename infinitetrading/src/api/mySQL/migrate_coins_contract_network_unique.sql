-- Fix: `coins.contract` was UNIQUE on its own, but OP-Stack chains share
-- predeploy addresses (WETH = 0x4200...0006 on both optimism and base).
--
-- Because updateCoins.R inserts with
--   ON DUPLICATE KEY UPDATE symbol = VALUES(symbol), network_id = VALUES(network_id)
-- loading base's WETH row silently *reassigned* optimism's row to base rather
-- than inserting a second one. The result was that getSymbol/getContract
-- returned null for WETH on optimism, breaking trading on that pair.
--
-- Every lookup already scopes by network_id, so the global uniqueness
-- constraint served no purpose. Scope it per-network instead.
--
-- Idempotent: safe to re-run.

ALTER TABLE coins DROP INDEX contract;
ALTER TABLE coins ADD UNIQUE KEY contract_network (contract, network_id);

-- Restore the row that was clobbered by the old constraint.
INSERT INTO coins (symbol, network_id, contract)
SELECT 'WETH', n.network_id, '0x4200000000000000000000000000000000000006'
FROM networks n
WHERE n.name = 'optimism'
ON DUPLICATE KEY UPDATE contract = VALUES(contract);
