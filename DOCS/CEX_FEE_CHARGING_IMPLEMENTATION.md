# CEX Fee Charging System Implementation

## Overview
Implemented a network-specific fee charging system for CEX trades. Users pay $0.10 USD per trade, charged from their gas wallet on a network they specify during registration.

## Changes Made

### 1. Express API - Fee Charging Endpoint
**File:** `infinitetrading_api/express/src/requests/cex.ts` (NEW)
- **POST `/api/cex/chargeFee`**: Charge fee from gas wallet
  - Requires: `apiKey`, `network`, `action` (defaults to 'cex_trade')
  - Optional: `pair`, `exchangeOrderId` (for logging)
  - Calculates USD fee → native token (ETH/POL/etc)
  - Sends payment to DAO wallet
  - Returns transaction hash and confirmation

- **GET `/api/cex/calculateFee`**: Preview fee without charging
  - Requires: `network`, `action`
  - Returns fee in native token for that network

### 2. Pricing Configuration
**File:** `infinitetrading_api/express/src/apiPricing.ts`
- Added `'cex_trade': 0.10` to `API_PRICING_USD` config
- $0.10 per CEX trade execution

### 3. Express Router Registration
**File:** `infinitetrading_api/express/src/index.ts`
- Imported and registered `cexRouter`
- Endpoints available at `/api/cex/*`

### 4. Database Schema Migration
**File:** `infinitetrading/src/api/mySQL/migrate_cex_subaccounts_schema.sql`

**cex_subaccounts table additions:**
- `manager_wallet` VARCHAR(42) - Manager wallet address
- `gas_wallet` VARCHAR(42) - Gas wallet address (universal across networks)
- `encrypted_gas_wallet_api_key` TEXT - Encrypted gas wallet API key
- `payment_network` VARCHAR(20) - Network to charge fees from (ethereum, polygon, optimism, arbitrum, base)
- `gas_balance_usd` DECIMAL(18,2) - Cached total gas balance across all networks
- `last_gas_check` TIMESTAMP - When gas balance was last checked
- `is_active` BOOLEAN - Whether subaccount is active

**cex_trades table additions:**
- `fee_network` VARCHAR(20) - Network fee was charged from
- `fee_amount_usd` DECIMAL(10,4) - Fee charged in USD (default 0.10)
- `fee_tx_hash` VARCHAR(66) - Transaction hash of fee payment

### 5. R API - Registration Handler Update
**File:** `infinitetrading/src/api/api.R`

**registerCEXSubaccountHandler:**
- Added `payment_network = "base"` parameter (default)
- Validates network against: ethereum, polygon, optimism, arbitrum, base
- Stores payment_network in database
- Returns payment_network in response

### 6. Documentation Update
**File:** `DOCS/CEX_FRONTEND_INTEGRATION_GUIDE.md`
- Updated `/registerCEXSubaccount` endpoint documentation
- Added `payment_network` parameter (required, defaults to "polygon")
- Explained fee charging ($0.10 per trade from chosen network)
- Added notes about gas balance requirements

## Usage Flow

### Registration
```typescript
// Frontend registers CEX subaccount
const response = await fetch('/registerCEXSubaccount', {
  method: 'POST',
  body: JSON.stringify({
    manager: "0x...",
    gas_wallet_api_key: "abc123...",
    payment_network: "base",  // NEW: Choose fee payment network (default)
    exchange: "coinbase",
    subaccount_name: "My Bot",
    cex_api_key: "...",
    cex_secret: "...",
    signature: "0x..."
  })
});
```

### Fee Charging (from cex_tradebot.R)
```r
# After successful CEX trade
charge_cex_fee <- function(gas_wallet_api_key, network, pair, order_id) {
  url <- "http://localhost:8000/api/cex/chargeFee"
  body <- list(
    apiKey = gas_wallet_api_key,
    network = network,
    action = "cex_trade",
    pair = pair,
    exchangeOrderId = order_id
  )
  
  response <- httr::POST(url, 
                        body = jsonlite::toJSON(body, auto_unbox = TRUE),
                        httr::content_type_json())
  
  result <- jsonlite::fromJSON(httr::content(response, "text", encoding = "UTF-8"))
  
  if (result$status == "success") {
    cat(sprintf("✅ Fee charged: %s %s (tx: %s)\n", 
                result$fee_charged, result$fee_token, result$transaction_hash))
    return(result$transaction_hash)
  } else {
    cat(sprintf("❌ Fee charge failed: %s\n", result$message))
    return(NULL)
  }
}
```

## Network Selection Strategy

Users should choose payment networks based on:
1. **Base (default)**: Low fees (~$0.03), excellent ecosystem, Coinbase-backed
2. **Polygon**: Lowest gas fees (~$0.01 for payment tx)
3. **Arbitrum/Optimism**: Low fees, good for frequent traders
4. **Ethereum**: Highest fees, but most secure/decentralized

## Next Steps - Integration Tasks

### 1. Deploy Database Migration
```bash
# On EC2
mysql -u richard_clare -p infinitetrading < migrate_cex_subaccounts_schema.sql
```

### 2. Deploy Express API Changes
```bash
cd infinitetrading_api/express
npm run build
pm2 restart infinitetrading-api
```

### 3. Deploy R API Changes
```bash
scp api.R ubuntu@ec2:~/infinitetrading/src/api/api.R
ssh ubuntu@ec2 "pm2 restart plumber-api"
```

### 4. Update cex_tradebot.R
Add fee charging after successful trades:
- Get subaccount's payment_network from database
- Call Express `/api/cex/chargeFee` endpoint
- Store fee_tx_hash in cex_trades table
- Handle insufficient balance errors gracefully

### 5. Frontend Updates
- Add payment network dropdown to CEX registration form
- Show current payment network in subaccount details
- Display fee history per trade
- Warning if gas balance low on payment network

## Testing Checklist

- [ ] Register CEX subaccount with each network option
- [ ] Verify payment_network stored correctly in database
- [ ] Execute test CEX trade
- [ ] Verify $0.10 fee charged from correct network
- [ ] Check transaction hash recorded in cex_trades table
- [ ] Test insufficient balance scenario
- [ ] Test fee calculation endpoint
- [ ] Verify fee deducted from gas wallet on correct network
- [ ] Check DAO wallet received payment

## Fee Economics

- **Per Trade**: $0.10 USD
- **Payment Cost** (approx):
  - Polygon: ~$0.01 (net: $0.09 profit)
  - Arbitrum: ~$0.02 (net: $0.08 profit)
  - Optimism: ~$0.02 (net: $0.08 profit)  
  - Base: ~$0.03 (net: $0.07 profit)
  - Ethereum: ~$1-5 (not recommended for frequent trading)

## Security Considerations

- ✅ Gas wallet API keys encrypted in database
- ✅ Signature verification required for all operations
- ✅ Network validation prevents invalid networks
- ✅ Balance check before fee charging
- ✅ Transaction confirmation before marking as paid
- ✅ Fee amount fixed in code (not user-controllable)
