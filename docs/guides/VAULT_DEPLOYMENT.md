# Vault Deployment Automation Guide

> **For AI Agents / integrators:** This document describes the full workflow
> to deploy a new automated trading strategy vault on the Infinite Trading
> Protocol. Follow each step in order. **Only call the public HTTPS API** —
> `https://api.infinitetrading.io`. It is the stable, documented surface meant
> for external consumers; do not call internal source directly.
>
> All routes below were checked against
> `infinitetrading_api/express/src/requests/*.ts` and confirmed live with
> `curl` against `https://api.infinitetrading.io`.

---

## Prerequisites

- A **manager wallet** (any EVM wallet you control) to own the vault and sign management calls.
- A **Chamber vault** — created manually at https://app.dhedge.org (the API does not create vaults; see Step 3).
- A **gas wallet** — a hot wallet the API generates for you, used to pay for and sign trade transactions. It must:
  - Be added as a **Trader** on the Chamber vault (via the Chamber UI or contract).
  - Hold native gas tokens on the target network (ETH on Optimism/Arbitrum/Base, POL on Polygon).

---

## Supported Networks & Protocols

| Network   | Native Gas Token | Short Positions |
|-----------|-----------------|-----------------|
| Optimism  | ETH             | ✅ (BTC1XBEAR, ETH1XBEAR) |
| Base      | ETH             | ❌ |
| Arbitrum  | ETH             | ✅ (BTC1XBEAR, ETH1XBEAR) |
| Polygon   | POL             | ❌ |
| Ethereum  | ETH             | ❌ |

**Protocol:** `dhedge` (default for all DeFi vault operations)
**Swap platform:** `auto` (default — automatic DEX routing). The legacy value
`odos` is **deprecated but still accepted** for backward compatibility; it is
silently routed to `auto`. Never rely on `odos` in new integrations.

---

## Step-by-Step Deployment Workflow

### Step 1: Create a Gas Wallet

> Skip this step if you already have a gas wallet API key.

```
GET /createGasWallet
Headers: (no auth required)
```

**Response:**
```json
{
  "status": "success",
  "status_code": 200,
  "address": "0x...",
  "private_key": "<64 hex chars, no 0x prefix>",
  "apiKey": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

⚠️ **Save the `private_key` and `apiKey` securely — they are never shown again.**
This is a brand-new keypair generated fresh per call; it belongs to nobody
until you fund and use it.

> This endpoint is intentionally hidden from the public API docs/OpenAPI spec
> (by design, so it isn't advertised for casual scraping) but remains publicly
> callable — it is not a secret route.

---

### Step 2: Fund the Gas Wallet

Send native gas tokens to the `address` returned in Step 1:
- **Optimism/Base/Arbitrum/Ethereum:** Send ETH (recommended: 0.01–0.05 ETH)
- **Polygon:** Send POL (recommended: 5–20 POL)

Check balance:
```
GET /getGasBalance?apiKey={gasWalletApiKey}&network={network}
```

`network` also accepts `all` to return balances across every supported
network in one call. `USD` (default `true`) controls whether the balance is
converted to a USD-denominated figure.

**Response (single network):**
```json
{
  "status": ["success"],
  "status_code": [200],
  "message": [0.0234]
}
```

> ✅ Proceed when balance > 0.

---

### Step 3: Create a Chamber Vault (Manual Step)

1. Go to https://app.dhedge.org
2. Connect your wallet (manager wallet).
3. Create a new vault — choose your network.
4. Fill in the vault's **name and description**. This is where any
   **disclaimers** you want shown in a frontend's vault-details view belong —
   Chamber stores this as on-chain/off-chain vault metadata and any frontend
   reading vault details (Chamber's own UI, or a custom frontend querying the
   Chamber SDK (@dhedge/v2-sdk)/subgraph) will surface it. **The Infinite Trading API does not
   have — and does not need — its own "set description" endpoint**; there is
   no such route in the Express source (`infinitetrading_api/express/src/requests/`)
   or the legacy R gateway.
5. Set the vault's **default fees** (Chamber's manager fee) at creation time —
   typically a streaming/management fee (% per year) and a performance fee
   (% of profits). These are Chamber-native parameters set once on the vault
   contract, not something this API configures. Once the vault is live, use
   `POST /mintManagerFee` (Step 9) to realize fees that have already accrued.
6. In vault settings, **add the gas wallet address (from Step 1) as a Trader**.
7. Copy the vault contract address (e.g., `0x7b84...`).

> This step cannot be automated via the Infinite Trading API — it requires
> interacting with the Chamber frontend or directly calling the Chamber factory
> contract.

---

### Step 4: Approve Assets for Trading

Before any trade can execute, each asset must be approved. Approve both the
sell asset and the buy asset. This sends a real ERC20-approval transaction
from the vault, so validate parameters carefully.

```
POST /approve
Body:
{
  "apiKey": "{gasWalletApiKey}",
  "network": "{network}",
  "protocol": "dhedge",
  "pool": "{vaultAddress}",
  "asset": "USDC"
}
```

`platform` is optional (defaults to `auto`). `asset` accepts either a symbol
(`USDC`, `WETH`, ...) or a raw contract address; symbols `BTC`, `USD`, `ETH`,
`MATIC`/`POL` are aliased to `WBTC`, `USDC`, `WETH`, `WMATIC` respectively.
Leveraged Toros tokens (symbol containing `BULL`/`BEAR`) are automatically
routed to the `toros` platform regardless of what you pass.

Repeat for each asset your strategy will trade. Common assets:

| Strategy Type | Assets to Approve |
|--------------|-------------------|
| BTC Long/Neutral | WBTC or cbBTC, USDC |
| ETH Long/Neutral | WETH, USDC |
| MORPHO Long/Neutral | MORPHO, USDC |
| BTC Short (Optimism/Arbitrum) | BTC1XBEAR, USDC |
| ETH Short (Optimism/Arbitrum) | ETH1XBEAR, USDC |

**Gas cost:** ~$0.01–0.05 per approval (one-time per asset per platform)

**Response:**
```json
{ "status": ["success"], "status_code": [200], "message": ["Asset approved"] }
```

On failure the API deliberately does **not** surface the underlying on-chain
error, to avoid leaking internal details to callers:
```json
{ "status": ["fail"], "status_code": [400], "message": ["Approve failed, try again or contact support"] }
```

> There is currently no separate vault-level "allowed assets list" endpoint —
> `/approve` is the only mechanism for authorizing an asset to trade.

---

### Step 5: Link the Gas Wallet to the Vault

Two related flows exist; use whichever matches your integration:

**Preferred (current, one-step):**
`POST /setBot` (Step 6) accepts the gas wallet directly and validates it
belongs to the vault — no separate link call needed for new integrations.

**Legacy (still supported):**
```
POST /linkGasWallet
Body:
{
  "apiKey": "{gasWalletApiKey}",
  "protocol": "dhedge",
  "pool": "{vaultAddress}",
  "network": "{network}"
}
```

This verifies on-chain that the gas wallet is a configured Trader on the pool
(status_code `1006` if not — go back to Step 3.6) and stores the association.
`DELETE /unlinkGasWallet` reverses it. New integrations should treat this as
optional/legacy; it is being consolidated into `/setBot` (see
[BOT_LINKING.md](../reference/BOT_LINKING.md)).

**Response:**
```json
{ "status": ["success"], "status_code": [200], "message": ["..."] }
```

---

### Step 6: Configure the Trading Bot

This is the core configuration step that activates automated trading. It
both persists the strategy configuration **and** immediately triggers a live
rebalance based on the current position vs. the new target side.

```
POST /setBot
Body:
{
  "apiKey": "{gasWalletApiKey}",
  "protocol": "dhedge",
  "pool": "{vaultAddress}",
  "network": "{network}",
  "pair": "{tradingPair}",
  "side": "neutral",
  "threshold": 1,
  "max_usd": 10000000,
  "slippage": 1,
  "share": 100,
  "platform": "auto",
  "lending": false
}
```

**Parameter Reference:**

| Parameter | Description | Values | Default |
|-----------|-------------|--------|---------|
| `pair` | Market pair to monitor | `BTC-USD`, `ETH-USD`, `MORPHO-USD`, etc. | required |
| `side` | Strategy direction | `long`, `short`, `neutral`, `hold` | required |
| `threshold` | Signal threshold (0–100), rounded to 2dp | Number 0–100 | `1` |
| `max_usd` | Max USD per trade, rounded to 2dp | Any number > 0 | `10000000` |
| `slippage` | Slippage tolerance % | `0.5`–`2.0` | `1` |
| `share` | % of vault to trade, rounded to 2dp | `1`–`100` | `100` |
| `platform` | Swap router | `auto` (recommended); `odos` accepted but deprecated | `auto` |
| `lending` | Auto-lend on Aave | `true`/`false` | `false` |

**Side meanings:**
- `long` → buys the asset (converts USDC → asset)
- `neutral` → sells to USDC (converts asset → USDC)
- `short` → opens a leveraged short (Optimism/Arbitrum only)
- `hold` → no action on new deposits or existing positions

**Validation (in order):** network/protocol/pool/apiKey basic check → `side`
must be one of `hold`/`neutral`/`short`/`long` (else `status_code 1008`) →
`short` requires network in `[arbitrum, optimism]` (else `400`) → `threshold`
in `[0,100]` → `share` in `[1,100]` → `max_usd` numeric `> 0` → apiKey must be
a gas wallet already linked to this exact `network`+`protocol`+`pool` (else
`401 Invalid API key`).

**Response reflects the DB write, not the trade result** — the response
tells you the bot config was saved; the actual rebalance trade this triggers
is executed asynchronously and its outcome is only logged server-side (a
`hold` side or a trade that doesn't clear `threshold` legitimately produces
no trade without failing this call):
```json
{ "status": "success", "status_code": 200, "message": "Sides submitted successfully" }
```

---

### Step 7: Verify Bot Status

```
GET /getAllBots?manager={managerAddress}&signature={eip191OrEip1271Signature}&network={network}
```

Requires a signature from the manager wallet over the message:
`"Sign this message to authenticate with Chamber Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations."`
(EIP-191 for EOAs, EIP-1271 for Safe multisigs). Omit `network` (or pass `all`)
to list bots across every network.

**Response:**
```json
{
  "status": ["success"],
  "status_code": [200],
  "bots": [
    {
      "pool": "0x...", "gasWallet": "0x...", "network": "optimism",
      "pair": "ETH-USD", "side": "neutral", "threshold": 1,
      "max_usd": 10000000, "share": 100, "platform": "auto", "slippage": 1
    }
  ]
}
```

---

### Step 8: Execute Initial Trade (Optional)

If you want to immediately take a position rather than waiting for the bot's
next cycle/signal change:

```
POST /vaultTrade
Body:
{
  "apiKey": "{gasWalletApiKey}",
  "protocol": "dhedge",
  "pool": "{vaultAddress}",
  "network": "{network}",
  "from": "USDC",
  "to": "WETH",
  "slippage": 0.5,
  "share": 100,
  "platform": "auto"
}
```

`from`/`to` accept symbols or contract addresses. An `amount` parameter (in
human units, e.g. `1.5`) takes precedence over `share` if both are supplied.

**Gas cost:** ~$0.05–0.20

**Response:**
```json
{ "status": ["success"], "status_code": [200], "message": ["trade executed"] }
```

---

### Step 9: Mint Accrued Manager Fees (Optional)

Realizes the performance/management fee already accrued by the vault (per
the fee % configured on Chamber in Step 3). This call is permissionless
on-chain — it doesn't move third-party funds, just triggers the mint.

```
POST /mintManagerFee
Body: { "apiKey": "{gasWalletApiKey}", "network": "{network}", "pool": "{vaultAddress}", "protocol": "dhedge" }
```

For minting fees across many vaults at once, see `GET|POST /mintManagerFeeBatch`.

---

## Example: Deploy crossOverV2 Strategy on ETH-USD (Optimism)

```bash
BASE_URL="https://api.infinitetrading.io"
API_KEY="your-gas-wallet-api-key"
VAULT="0xyourvaultaddress"
NETWORK="optimism"

# 1. Check gas balance
curl "$BASE_URL/getGasBalance?apiKey=$API_KEY&network=$NETWORK"

# 2. Approve WETH for swaps
curl -X POST "$BASE_URL/approve" \
  -H "Content-Type: application/json" \
  -d '{"apiKey":"'"$API_KEY"'","network":"'"$NETWORK"'","protocol":"dhedge","pool":"'"$VAULT"'","asset":"WETH"}'

# 3. Approve USDC for swaps
curl -X POST "$BASE_URL/approve" \
  -H "Content-Type: application/json" \
  -d '{"apiKey":"'"$API_KEY"'","network":"'"$NETWORK"'","protocol":"dhedge","pool":"'"$VAULT"'","asset":"USDC"}'

# 4. Set bot to neutral (safe default until strategy signals long)
curl -X POST "$BASE_URL/setBot" \
  -H "Content-Type: application/json" \
  -d '{
    "apiKey":"'"$API_KEY"'",
    "protocol":"dhedge",
    "pool":"'"$VAULT"'",
    "network":"'"$NETWORK"'",
    "pair":"ETH-USD",
    "side":"neutral",
    "threshold":1,
    "slippage":1,
    "share":100
  }'
```

---

## Strategy → Side Mapping

| Strategy Signal | `setBot` side | Behavior |
|----------------|---------------|----------|
| `LONG` | `long` | Swaps 100% of USDC → asset |
| `NEUTRAL` / Exit | `neutral` | Swaps 100% of asset → USDC |
| `HOLD` | `hold` | No trades, keep current position |
| `SHORT` (Optimism/Arb only) | `short` | Opens leveraged bear position |

## Automated Strategy Loop (R / crossOverV2.R)

The production strategy file (`/home/ubuntu/infinitetrading/src/strategies/crossOverV2.R`)
runs in a loop and calls the public `/setBot` HTTPS endpoint (never the
Express/R source in-process) when the signal changes:

```r
# Signal to side mapping
if (new_signal == "LONG" && current_side != "long") {
  call_setBot(pool, network, pair, side="long")
} else if (new_signal == "NEUTRAL" && current_side != "neutral") {
  call_setBot(pool, network, pair, side="neutral")
}
```

The strategy sleeps 6 hours between cycles (matching the 6H candle timeframe).

---

## Monitoring

### Check all active bots:
```
GET /getAllBots?manager={managerAddress}&signature={signature}
```

### Check vault composition (enriched, symbol-resolved):
```
GET /poolComposition?apiKey={gasWalletApiKey}&protocol=dhedge&pool={vaultAddress}&network={network}
```

### Get LLM-readable API documentation:
```
GET /llmIntrospect?apiKey={gasWalletApiKey}
```

---

## Error Reference

| Code | Meaning | Fix |
|------|---------|-----|
| `1000` | Invalid/unrecognized network | Use one of: base, optimism, arbitrum, polygon, ethereum |
| `1001` | Invalid protocol | Use `dhedge` |
| `1002` | Malformed apiKey | Check the UUID-shaped key from `/createGasWallet` |
| `1004` | Invalid pool address | Must be a `0x...` vault contract address |
| `1006` | Wallet not a configured Trader on the pool | Add the gas wallet as a Trader in Chamber (Step 3.6) |
| `1007` | Invalid `share` (must be 1–100) | Set `share` between 1 and 100 |
| `1008` | Invalid `side` | Use: `long`, `short`, `hold`, or `neutral` |
| `400` | Bad parameters | Check network/protocol/pool params |
| `401` | Invalid/unlinked API key | Confirm the gas wallet is linked to this exact pool+network |
| `500` | Internal revert / no payment | Gas wallet not funded or not a trader on vault |

---

## Quick Reference Card

```
Create gas wallet:    GET  /createGasWallet
Check gas balance:    GET  /getGasBalance?apiKey=&network=
Approve asset:        POST /approve            {apiKey, network, protocol, pool, asset, platform}
Link gas wallet:      POST /linkGasWallet      {apiKey, protocol, pool, network}   (legacy, optional)
Set bot:              POST /setBot             {apiKey, protocol, pool, network, pair, side, ...}
Get all bots:         GET  /getAllBots?manager=&signature=&network=
Execute trade:        POST /vaultTrade         {apiKey, protocol, pool, network, from, to, share}
Delete bot:           DELETE /deleteBot        {apiKey, protocol, pool, network}
Mint manager fee:     POST /mintManagerFee     {apiKey, network, pool, protocol}
Pool composition:     GET  /poolComposition?apiKey=&protocol=dhedge&pool=&network=
API docs (LLM):       GET  /llmIntrospect?apiKey=
```

> Note: a dedicated `/getBotStatus` and `/isPoolTrader` existed in the legacy
> R gateway but have **no live Express port** as of this migration — use
> `/getAllBots` (filtered client-side by pool) to check bot state, and the
> `1006` error from `/setBot`/`/linkGasWallet` to detect a trader-authorization
> problem instead of pre-checking with `/isPoolTrader`.
