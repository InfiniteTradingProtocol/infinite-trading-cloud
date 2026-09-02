# Simplify Bot Setup: Remove linkGasWallet Step

## Current Flow (two-step, redundant)
1. `associateGasWallet` → `gas_wallets` row with `pool=NULL` (wallet belongs to manager)
2. `linkGasWallet` → second `gas_wallets` row with `pool=<vault>` (wallet assigned to vault)
3. Tradebot: `pool → linked gas_wallets row → token → private key`

## Proposed Flow (one-step)
1. `associateGasWallet` → wallet registered to manager (only row ever needed)
2. `setBot` → validates gas wallet belongs to manager, stores `gas_wallet` address in `dhedge_sides`
3. Tradebot: `pool → dhedge_sides.gas_wallet → gas_wallets WHERE wallet_address=? AND pool IS NULL → token → private key`
4. Before execution: verify `gas_wallet == pool.trader` on-chain — if mismatch, set `is_active=0` and skip

---

## Changes Required

### 1. DB Schema
- Add `gas_wallet VARCHAR(42)` column to `dhedge_sides`
- `gas_wallets` linked rows (`pool IS NOT NULL`) become unused — can be deprecated

### 2. `setBot` / `setSide` handler (`api.R` + `db.R`)
- Accept `gasWallet` param
- Validate `gasWallet` is in `gas_wallets WHERE manager=? AND pool IS NULL`
- Store in `dhedge_sides.gas_wallet`

### 3. Tradebot execution path (`defi.R` / `tradebot`)
- Replace `getAPIKey(network, protocol, pool)` lookup via linked row
- New lookup: `SELECT token FROM gas_wallets WHERE wallet_address = (SELECT gas_wallet FROM dhedge_sides WHERE pool=? AND network=?) AND pool IS NULL`
- Add on-chain trader check: call dHEDGE pool contract `trader()` — if != `gas_wallet`, set `is_active=0` on the `dhedge_sides` row and skip execution

### 4. `getAllBots` (`db.R`)
- `getBots()` already JOINs `gas_wallets` + `dhedge_sides` — update to use `dhedge_sides.gas_wallet` instead of `gas_wallets WHERE pool IS NOT NULL`

### 5. `deleteBot` / `unlinkGasWallet`
- `deleteBot` deletes from `dhedge_sides` — no change needed
- `unlinkGasWallet` becomes redundant — can be removed or aliased to `deleteBot`

### 6. Frontend
- Remove `linkGasWallet` step from bot setup flow
- `setBot` form: user selects which associated gas wallet to use for that vault

### 7. Gateway endpoints
- Remove `linkGasWallet.R` and `unlinkGasWallet.R` from active endpoints (or leave as no-ops for backward compat)

---

## Migration
- Existing bots already have linked rows in `gas_wallets (pool IS NOT NULL)` — need a one-time migration to populate `dhedge_sides.gas_wallet` from those rows before removing the link rows
- SQL: `UPDATE dhedge_sides ds JOIN gas_wallets gw ON gw.pool = ds.pool AND gw.network = ds.network SET ds.gas_wallet = gw.wallet_address`
