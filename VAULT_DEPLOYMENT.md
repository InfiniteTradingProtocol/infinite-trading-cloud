# Vault Deployment Automation Guide

> **For AI Agents:** This document describes the full workflow to deploy a new automated trading strategy vault on the Infinite Trading Protocol. Follow each step in order. All API calls use `https://api.infinitetrading.io`.

---

## Prerequisites

- You need a **manager API key** (from https://www.infinitetrading.io/managers)
- You need a **dHEDGE vault address** (create manually at https://app.dhedge.org — the API does not create vaults)
- The gas wallet's Ethereum address must be **added as a Trader** on the dHEDGE vault (done via dHEDGE UI or contract)
- The gas wallet must hold **native gas tokens** on the target network (ETH on Optimism/Arbitrum/Base, POL on Polygon)

---

## Supported Networks & Protocols

| Network   | Native Gas Token | Short Positions |
|-----------|-----------------|-----------------|
| Optimism  | ETH             | ✅ (BTC1XBEAR, ETH1XBEAR) |
| Base      | ETH             | ❌ |
| Arbitrum  | ETH             | ✅ (BTC1XBEAR, ETH1XBEAR) |
| Polygon   | POL             | ❌ |

**Protocol:** `dhedge` (default for all DeFi vault operations)
**Swap Platform:** `odos` (DEX aggregator, default for all trades)

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
  "address": "0x...",
  "private_key": "0x...",
  "apiKey": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

⚠️ **Save the `private_key` and `apiKey` securely — they are never shown again.**

---

### Step 2: Fund the Gas Wallet

Send native gas tokens to the `address` returned in Step 1:
- **Optimism/Base/Arbitrum:** Send ETH (recommended: 0.01–0.05 ETH)
- **Polygon:** Send POL (recommended: 5–20 POL)

Check balance:
```
GET /getGasBalance?apiKey={gasWalletApiKey}&network={network}
```

**Response:**
```json
{
  "status": "success",
  "balance": 0.02,
  "currency": "ETH",
  "network": "optimism"
}
```

> ✅ Proceed when balance > 0.

---

### Step 3: Create a dHEDGE Vault (Manual Step)

1. Go to https://app.dhedge.org
2. Connect your wallet (manager wallet)
3. Create a new vault — choose your network
4. In vault settings, **add the gas wallet address as a Trader**
5. Copy the vault contract address (e.g., `0x7b84...`)

> This step cannot be automated via API — it requires interacting with the dHEDGE frontend or directly calling the dHEDGE factory contract.

---

### Step 4: Verify Gas Wallet is a Pool Trader

```
GET /isPoolTrader?apiKey={gasWalletApiKey}&protocol=dhedge&network={network}&pool={vaultAddress}
```

**Expected Response:**
```json
{
  "status": "success",
  "is_trader": true
}
```

> ⚠️ If `is_trader` is false, return to Step 3 and add the gas wallet as a Trader on the vault.

---

### Step 5: Approve Assets for Trading

Before any trade can execute, each asset must be approved. Approve both the sell asset and the buy asset.

```
POST /approve
Body:
{
  "apiKey": "{gasWalletApiKey}",
  "network": "{network}",
  "protocol": "dhedge",
  "pool": "{vaultAddress}",
  "asset": "USDC",
  "platform": "odos"
}
```

Repeat for each asset your strategy will trade. Common assets:

| Strategy Type | Assets to Approve |
|--------------|-------------------|
| BTC Long/Neutral | WBTC or cbBTC, USDC |
| ETH Long/Neutral | WETH, USDC |
| MORPHO Long/Neutral | MORPHO, USDC |
| BTC Short (Optimism) | BTC1XBEAR, USDC |
| ETH Short (Optimism) | ETH1XBEAR, USDC |

**Gas cost:** ~$0.01–0.05 per approval (one-time per asset per platform)

**Response:**
```json
{
  "status": "success",
  "status_code": 200,
  "message": "Asset approved successfully"
}
```

---

### Step 6: Configure the Trading Bot

This is the core configuration step that activates automated trading.

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
  "platform": "odos",
  "lending": false
}
```

**Parameter Reference:**

| Parameter | Description | Values | Default |
|-----------|-------------|--------|---------|
| `pair` | Market pair to monitor | `BTC-USD`, `ETH-USD`, `MORPHO-USD`, etc. | required |
| `side` | Strategy direction | `long`, `short`, `neutral`, `hold` | required |
| `threshold` | Signal threshold (0–100) | Number 0–100 | `1` |
| `max_usd` | Max USD per trade | Any number | `10000000` |
| `slippage` | Slippage tolerance % | `0.5`–`2.0` | `1` |
| `share` | % of vault to trade | `1`–`100` | `100` |
| `platform` | Swap router | `odos` | `odos` |
| `lending` | Auto-lend on Aave | `true`/`false` | `false` |

**Side meanings:**
- `long` → buys the asset (converts USDC → asset)
- `neutral` → sells to USDC (converts asset → USDC)
- `short` → opens a leveraged short (Optimism/Arbitrum only)
- `hold` → no action on new deposits or existing positions

**Response:**
```json
{
  "status": "success",
  "status_code": 200,
  "message": "Bot configured successfully"
}
```

---

### Step 7: Verify Bot Status

```
GET /getBotStatus?apiKey={gasWalletApiKey}&protocol=dhedge&network={network}&pool={vaultAddress}
```

**Response:**
```json
{
  "status": "success",
  "side": "neutral",
  "pair": "BTC-USD",
  "threshold": 1,
  "is_active": true
}
```

---

### Step 8: Execute Initial Trade (Optional)

If you want to immediately take a position rather than waiting for the bot cycle:

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
  "platform": "odos"
}
```

**Gas cost:** ~$0.05–0.20

---

## Example: Deploy crossOverV2 Strategy on ETH-USD (Optimism)

This example deploys the EMA Crossover V2 strategy on an Optimism vault trading ETH-USD.

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
  -d '{"apiKey":"'"$API_KEY"'","network":"'"$NETWORK"'","protocol":"dhedge","pool":"'"$VAULT"'","asset":"WETH","platform":"odos"}'

# 3. Approve USDC for swaps
curl -X POST "$BASE_URL/approve" \
  -H "Content-Type: application/json" \
  -d '{"apiKey":"'"$API_KEY"'","network":"'"$NETWORK"'","protocol":"dhedge","pool":"'"$VAULT"'","asset":"USDC","platform":"odos"}'

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
    "share":100,
    "platform":"odos"
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

---

## Automated Strategy Loop (R / crossOverV2.R)

The production strategy file (`/home/ubuntu/infinitetrading/src/strategies/crossOverV2.R`) runs in a loop and calls `/setBot` when the signal changes:

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
GET /getAllBots?apiKey={gasWalletApiKey}
```

### Check vault composition:
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
| `1006` | Wrong endpoint called | Check you're using the right route |
| `1007` | Invalid `share` (must be 1–100) | Set `share` between 1 and 100 |
| `1008` | Invalid `side` | Use: `long`, `short`, `hold`, or `neutral` |
| `400` | Bad parameters | Check network/protocol/pool params |
| `401` | Invalid API key | Regenerate key at manager dashboard |
| `500` | Internal revert / no payment | Gas wallet not funded or not a trader on vault |

---

## Quick Reference Card

```
Create gas wallet:    GET  /createGasWallet
Check gas balance:    GET  /getGasBalance?apiKey=&network=
Verify trader:        GET  /isPoolTrader?apiKey=&protocol=dhedge&network=&pool=
Approve asset:        POST /approve          {apiKey, network, protocol, pool, asset, platform}
Set bot:              POST /setBot           {apiKey, protocol, pool, network, pair, side, ...}
Get bot status:       GET  /getBotStatus?apiKey=&protocol=dhedge&network=&pool=
Execute trade:        POST /vaultTrade       {apiKey, protocol, pool, network, from, to, share}
Get all bots:         GET  /getAllBots?apiKey=
Delete bot:           DEL  /deleteBot        {apiKey, protocol, pool, network}
Pool composition:     GET  /poolComposition?apiKey=&protocol=dhedge&pool=&network=
API docs (LLM):       GET  /llmIntrospect?apiKey=
```
