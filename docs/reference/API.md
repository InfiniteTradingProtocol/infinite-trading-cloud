# API Reference

Live, browsable docs: **https://api.infinitetrading.io/__docs__/**
(spec at `/openapi.json`)

Those are generated from the code, so they are always current. This document
covers the conventions the generated docs don't express.

---

## Base URL

```
https://api.infinitetrading.io
```

Most endpoints accept **both GET and POST**; handlers merge `req.query` and
`req.body`, so parameters can be sent either way.

## Authentication

Two schemes:

| Scheme | Used by | Value |
|---|---|---|
| Per-user API key | Almost everything | A UUID issued by `/getNewApiKey`. Identifies the gas wallet that pays for transactions and is what usage is billed against. |
| Shared frontend key | `getCandles`, `getTicks`, `getAllYields`, `getTotalYield`, `getGasWalletPools`, `getAssociatedGasWallets` | A single shared token, configured as `FRONTEND_API_KEY`. Read-only data only. |

Some endpoints are additionally gated on the caller being the vault's trader.
Permissionless on-chain operations (for example manager-fee minting, which
anyone may call) deliberately are not.

## Common parameters

| Parameter | Notes |
|---|---|
| `network` | `base`, `optimism`, `arbitrum`, `polygon`, `ethereum` (alias `mainnet`), `hyperliquid` |
| `protocol` | `dhedge` (default). `chamber` is the current brand name and is accepted as an alias. |
| `pool` | Vault contract address, `0x…` (40 hex chars) |
| `platform` | Execution venue. Default `auto` — the executor walks a per-network DEX fallback chain, skipping banned or non-whitelisted venues. |
| `asset` | Symbol (`USDC`, `WETH`) or contract address |
| `share` | Percentage 0-100 of available balance. **Takes precedence over `amount`.** |
| `amount` | Absolute amount; ignored when `share` is given |

### Deprecated values are accepted, never rejected

Live strategies still send retired parameter values, so the API absorbs them
rather than erroring:

- `platform=odos` → silently routed to `auto` (ODOS is sunset)
- `protocol=chamber` → normalized to `dhedge` before any handler sees it

## Response format

Successful responses are ordinary JSON.

**Validation failures return HTTP 200**, with each field as a 1-element array.
This is a holdover from the original R/jsonlite wire format that live
strategies parse; changing it would break them.

```json
{
  "status": ["fail"],
  "status_code": ["1000"],
  "message": ["Unrecognized network"]
}
```

| Code | Meaning |
|---|---|
| 1000 | Unrecognized network |
| 1001 | Unrecognized protocol |
| 1002 | Invalid API key |
| 1004 | Invalid pool address |
| 1010 | Missing required parameter |

Execution failures (as opposed to validation) return HTTP 400 with a flat
object carrying `status`, `status_code` and `error_type`.

## Rate limits

| Layer | Limit |
|---|---|
| nginx | 30 requests/minute, burst 20 — exceeding it returns **503 HTML**, not JSON |
| Express | 600/minute default; 10/minute on `llmIntrospect` |

Clients that burst should back off and retry; a 503 here is throttling, not an
outage.

## Endpoint groups

| Group | Purpose |
|---|---|
| Managers | `vaultTrade`, `approve`, `setBot`, `deleteBot`, `mintManagerFee` |
| Admin | `mintManagerFeeBatch`, `mintAllFeesByManager` |
| Lending | `lend`, `unlend`, `borrow`, `repay`, plus per-protocol routers (`aaveV3/*`, `compoundV3/*`, `fluid/*`) |
| Liquidity | `addLiquidity`, `removeLiquidity` |
| Pools | `poolComposition` |
| Market Data | `getCandles`, `getTicks` |
| Tokens | `getSymbol`, `getContract` |
| Gas Wallets | `getGasBalance` and the gas-wallet linking endpoints |
| CEX | Subaccount registration, sides, bot management |
| Wallet | `getNewApiKey` |

### Batched fee minting

Two endpoints mint accrued manager fees for many vaults in **one** transaction
via Multicall3:

- `mintManagerFeeBatch` — you supply the pool list.
- `mintAllFeesByManager` — you supply a *manager address*; it discovers the
  vaults itself and skips any with a zero fee.

Both accept `dryRun=true`, which simulates and quotes without submitting.

`mintAllFeesByManager` discovers vaults from this system's known-vault set and
verifies each one's manager on-chain. A vault this system has no record of
won't be found, so the response reports `scanned` alongside `matched` —
`matched: 0` means "none found in the known set", not necessarily "no fees
owed".

## Documentation visibility

The docs page lists only endpoints marked public in
`infinitetrading/src/api/helpers/endpoints.R`. Endpoints in `hidden_endpoints`
are omitted from the docs but remain **fully public and callable** — hiding is
cosmetic, not access control.
