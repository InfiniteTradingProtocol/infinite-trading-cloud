# Infinite Trading System Architecture Documentation

> **For AI Agents & MCPs**: This document provides deep system understanding to prevent coding mistakes

## 📋 Table of Contents
1. [System Overview](#system-overview)
2. [SSH & Environment Setup](#ssh--environment-setup)
3. [Service Architecture](#service-architecture)
4. [Nginx Routing](#nginx-routing)
5. [Gateway Error Handling](#gateway-error-handling)
6. [Express API Error Handling](#express-api-error-handling)
7. [Database Architecture](#database-architecture)
8. [Deployment Workflow](#deployment-workflow)

---

## System Overview

### **Current Production Environment**
- **Server**: AWS EC2 (Ubuntu)
- **IP**: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`
- **Domain**: `api.infinitetrading.io` (HTTPS with Let's Encrypt)
- **SSH Key**: `~/.ssh/macbook.pem`

### **Technology Stack**
| Component | Technology | Port | Management |
|-----------|-----------|------|------------|
| Express API | Node.js + TypeScript | 8000 | PM2 |
| API Gateway | R + Plumber | 8003 | screen session `gateway` |
| Legacy API | R + Plumber | 8002 | screen session `plumber` |
| Database | MySQL | 3306 | systemd |
| Cache | Redis | 6379 | systemd |
| Web Server | Nginx | 80/443 | systemd |
| Strategy Bots | R Scripts | N/A | 9 screen sessions |
| Data Collectors | R Scripts | N/A | 5 screen sessions |

---

## SSH & Environment Setup

### **SSH Connection**
```bash
# Standard connection
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# With port forwarding for local debugging
ssh -i ~/.ssh/macbook.pem -L 8003:localhost:8003 -L 8000:localhost:8000 ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

### **File Transfer (rsync)**
```bash
# Deploy Express API
rsync -avz --exclude 'node_modules' --exclude 'logs' \
  -e "ssh -i ~/.ssh/macbook.pem" \
  ./express/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/

# Deploy Gateway
rsync -avz -e "ssh -i ~/.ssh/macbook.pem" \
  ./gateway/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading/src/api/gateway/
```

### **Environment Variables**

#### **Express API** (`/home/ubuntu/infinitetrading_api/express/.env`)
```bash
NODE_ENV=production
PORT=8000
REDIS_URL=redis://localhost:6379

# RPC Providers
DRPC_API_KEY=<drpc_key>
ALCHEMY_API_KEY=<alchemy_key>
INFURA_API_KEY=<infura_key>

# Private keys for gas wallets
INFINITETRADING_PRIVATE_KEY=<wallet_private_key>
```

#### **R API** (`/home/ubuntu/infinitetrading/src/.env`)
```bash
db_user="richard_clare"
db_password="<db_password>"
dbname="infinitetrading"
host="localhost"

# API Keys
cmc_apikey="<coinmarketcap_key>"
ITP_APIKEY="<internal_api_key>"
COINGECKO_APIKEY="<coingecko_key>"
TG_BOT="<telegram_bot_token>"
TG_CHAT_ID="<telegram_chat_id>"
ALCHEMY_BALANCES_APIKEY="<alchemy_key>"
```

---

## Service Architecture

### **Directory Structure**
```
/home/ubuntu/
├── infinitetrading_api/              # Express TypeScript API
│   └── express/
│       ├── src/
│       │   ├── requests/
│       │   │   ├── trade.ts          # Trading endpoints
│       │   │   ├── admin.ts          # Admin endpoints
│       │   │   ├── invest.ts         # Investment endpoints
│       │   │   ├── lending.ts        # Lending/borrowing
│       │   │   └── pricing.ts        # Price data
│       │   ├── utils/                # Utilities (RetryProvider, ERC20, etc)
│       │   ├── lib/                  # Redis, helpers
│       │   └── index.ts              # Main entry point
│       ├── build/                    # Compiled JavaScript
│       ├── ecosystem.config.js       # PM2 configuration
│       └── package.json
│
├── infinitetrading/                   # R-based system
│   ├── src/
│   │   ├── api/
│   │   │   ├── gateway/              # API Gateway (port 8003)
│   │   │   │   ├── gateway.R         # Main gateway server
│   │   │   │   └── endpoints/        # Endpoint handlers
│   │   │   ├── api.R                 # Legacy API (port 8002)
│   │   │   ├── db.R                  # Database functions
│   │   │   ├── trading.R             # Trade bot
│   │   │   ├── gasMonitor.R          # Gas monitoring
│   │   │   └── helpers/
│   │   │       ├── apiHelpers.R      # Validation, error codes
│   │   │       └── endpoints.R       # Endpoint registry
│   │   ├── strategies/               # Trading strategies
│   │   │   ├── eth_ema_11_33_crossover.R
│   │   │   ├── cbBTC_probability_model.R
│   │   │   ├── superTrend.R
│   │   │   ├── Velo1DBot.R
│   │   │   └── ... (9 total bots)
│   │   ├── db/                       # Data collection
│   │   │   ├── candles.py            # Price candles
│   │   │   ├── messages.py           # Messaging
│   │   │   └── db.py                 # DB utilities
│   │   └── tradebot/                 # Trading infrastructure
│   │       ├── pools.R               # Pool monitoring
│   │       └── defi.R                # DeFi interactions
│   └── defi/                         # DeFi utilities
│       ├── defi.py
│       └── poolInfo.py
│
└── startup.sh                         # System startup script
```

### **Service Startup Order** (`startup.sh`)
1. **Redis** - Cache & rate limiting
2. **Plumber API** (port 8002) - Legacy R API
3. **Gateway** (port 8003) - Main API gateway
4. **Express API** (port 8000) - PM2 managed, auto-restart
5. **Data Collectors** - coinbase, messages, models, yields
6. **Trading Infrastructure** - pools, prices
7. **Gas Monitoring** - gasMonitor
8. **Trade Bots** - tradeBot
9. **Strategy Bots** - 9 concurrent strategy sessions

### **PM2 Management** (Express API only)
```bash
# Check status
pm2 list

# View logs
pm2 logs infinitetrading-api

# Restart after deployment
pm2 restart ecosystem.config.js

# PM2 is configured to auto-start on boot via systemd
```

### **Screen Sessions Management** (R services)
```bash
# List all sessions
screen -ls

# Attach to a session
screen -r gateway

# Detach from session
# Press: Ctrl+A, then D

# Kill a session
screen -X -S gateway quit

# Restart gateway example
screen -r gateway
# Press Ctrl+C (stop)
# Press Ctrl+A then D (detach)
```

---

## Nginx Routing

### **Configuration Files**
- **Main config**: `/etc/nginx/sites-enabled/api.infinitetrading.io`
- **Endpoints**: `/etc/nginx/snippets/itp_endpoints.conf` (auto-generated)
- **SSL Certs**: `/etc/letsencrypt/live/api.infinitetrading.io/`

### **Routing Logic**

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       │ HTTPS (443)
       ▼
┌─────────────────┐
│     Nginx       │
│ api.infinite    │
│  trading.io     │
└────────┬────────┘
         │
         ├─── Rate Limiting (600 req/60s)
         ├─── Security Headers
         ├─── Path Validation
         │
         ▼
    Route Decision:
         │
         ├─── /openapi.json ──────────────► Gateway (8003)
         ├─── /__docs__/ ─────────────────► Gateway (8003)
         │
         ├─── Gateway Endpoints ──────────► Gateway (8003)
         │    (approve, vaultTrade, lend,
         │     poolComposition, etc.)
         │
         ├─── Express Endpoints ──────────► Gateway (8003) ──► Express (8000)
         │    (trade, invest, lending)          │ proxy_pass
         │
         └─── Legacy Endpoints ───────────► Plumber API (8002)
              (yields, gas wallets)
```

### **When to Modify Nginx**

#### **Adding a New Gateway Endpoint** (R Plumber)
1. Add endpoint name to `/home/ubuntu/infinitetrading/src/api/helpers/endpoints.R`:
   ```r
   endpoints <- c("approve", "vaultTrade", "yourNewEndpoint")
   ```

2. Create endpoint file: `/home/ubuntu/infinitetrading/src/api/gateway/endpoints/yourNewEndpoint.R`

3. **Nginx will auto-update** via `/etc/nginx/snippets/itp_endpoints.conf` (regenerated by gateway)

4. Reload Nginx:
   ```bash
   sudo nginx -t           # Test configuration
   sudo nginx -s reload    # Apply changes
   ```

#### **Adding a New Express Endpoint** (TypeScript)
1. Add route in `/home/ubuntu/infinitetrading_api/express/src/requests/*.ts`
2. **No Nginx changes needed** - Gateway already proxies to Express
3. Deploy Express API:
   ```bash
   npm run build
   pm2 restart ecosystem.config.js
   ```

#### **Key Rules:**
- ✅ **Gateway endpoints** (R): Update `endpoints.R` + reload Nginx
- ✅ **Express endpoints** (TS): Just deploy, no Nginx change
- ⚠️ **Never edit** `/etc/nginx/snippets/itp_endpoints.conf` manually (auto-generated)

---

## Gateway Error Handling

### **Error Code System** (`apiHelpers.R`)

The Gateway uses a structured error code system with status codes in the `1000-1999` range:

| Code | Error Type | Description |
|------|-----------|-------------|
| `1000` | `UNRECOGNIZED_NETWORK` | Invalid network parameter (must be: ethereum, arbitrum, optimism, polygon, base) |
| `1001` | `UNRECOGNIZED_PROTOCOL` | Invalid protocol parameter (must be: dhedge) |
| `1002` | `INVALID_API_KEY` | API key format invalid or unauthorized |
| `1003` | `INVALID_PAIR` | Trading pair not supported on network |
| `1004` | `INVALID_POOL_ADDRESS` | Pool address is not a valid Ethereum address |
| `1005` | `INVALID_ETHEREUM_ADDRESS` | Wallet/contract address is not valid |
| `1006` | `INVALID_TRADER` | Wallet not configured as trader for pool |
| `1007` | `INVALID_PARAMETER` | Generic parameter validation error (e.g., share not in 1-100 range) |

### **Error Response Format**

```json
{
  "status": "fail",
  "status_code": "1000",
  "message": "Unrecognized network"
}
```

### **Validation Flow** (`basic_check` function)

```r
basic_check <- function(network, protocol, apiKey, pool, wallet, pair, trader) {
  network <- tolower(network)
  
  # 1. Network validation
  if (!is_valid_network(network)) 
    return(list(status="fail", status_code="1000", message="Unrecognized network"))
  
  # 2. Protocol validation
  if (!is_valid_protocol(protocol)) 
    return(list(status="fail", status_code="1001", message="Unrecognized protocol"))
  
  # 3. API Key validation
  if (!isValidAPIKey(apiKey)) 
    return(list(status="fail", status_code="1002", message="Invalid API Key"))
  
  # 4. Trading pair validation
  if (!is.null(pair) && !is_valid_pair(network, pair)) 
    return(list(status="fail", status_code="1003", message="Invalid Pair"))
  
  # 5. Pool address validation
  if (!is.null(pool) && !isValidEthereumAddress(pool)) 
    return(list(status="fail", status_code="1004", message="Invalid Pool Address"))
  
  # 6. Wallet address validation
  if (!is.null(wallet) && !isValidEthereumAddress(wallet)) 
    return(list(status="fail", status_code="1005", message="Invalid Ethereum Address"))
  
  # 7. Trader authorization validation
  if (!is.null(trader) && !isValidTrader(protocol, pool, trader)) 
    return(list(status="fail", status_code="1006", message="The trader wallet is not configured as a trader in the specified pool"))
  
  return(list(status="success"))
}
```

### **Rate Limiting** (Gateway level)
- **Limit**: 600 requests per 60 seconds per IP
- **Response**: HTTP 429 with error payload
- **Tracking**: In-memory store (resets on gateway restart)

```r
rate_limit_middleware <- function(req) {
  client_ip <- req$HTTP_X_REAL_IP
  max_requests <- 600
  time_window <- 60
  
  if (length(request_tracker[[client_ip]]) > max_requests) {
    res$status <- 429
    res$body <- toJSON(list(error = "Rate limit exceeded"), auto_unbox = TRUE)
    return(res)
  }
  
  plumber::forward()
}
```

### **Endpoint Example** (`vaultTrade`)

```r
vaultTradeHandler <- function(network, protocol, platform, apiKey, pool, from, to, slippage, share, amount) {
  # 1. Validate all parameters
  check = basic_check(network=network, protocol=protocol, pool=pool, apiKey=apiKey)
  if (check$status == "fail") { return(check) }
  
  # 2. Additional parameter validation
  if (share < 1 || share > 100) {
    return(list(
      status="fail",
      status_code=1007,
      message="error: share is not an integer between [1,100]"
    ))
  }
  
  # 3. Proxy to Express API
  url <- paste0(pep, "vaultTrade?apiKey=", apiKey, "...")
  response <- GET(url)
  parsed_response <- fromJSON(content(response, "text"))
  
  return(parsed_response)
}
```

### **Gateway → Express Proxying**

The Gateway acts as a **proxy layer** with validation:

```
Client → Gateway (validation) → Express (execution) → Blockchain
         ├─ Rate limit
         ├─ Parameter validation
         ├─ API key check
         └─ Error code mapping
```

**Important**: Gateway validates, Express executes. Both can return errors.

---

## Express API Error Handling

### **✅ STANDARDIZED** Error Response Format

All Express endpoints now return consistent error responses:

```typescript
{
  "status": "fail",
  "status_code": 2001,  // Numeric code for programmatic handling
  "message": "Insufficient gas in wallet",  // Human-readable message
  "error_type": "insufficient_gas",  // Machine-readable type
  "details": {  // Optional additional context
    "wallet_address": "0x...",
    "ban_duration_minutes": 15
  }
}
```

### **Express Error Codes** (Range: 2000-5999)

| Range | Category | Description |
|-------|----------|-------------|
| 2000-2999 | Trading Errors | Trade execution, gas, allowance, slippage |
| 3000-3999 | Admin Errors | Pool management, wallet operations |
| 4000-4999 | Investment Errors | Deposits, withdrawals |
| 5000-5999 | Lending Errors | Borrow, repay, lend, unlend |

#### **Trading Errors (2000-2999)**
| Code | Error Type | Description |
|------|-----------|-------------|
| `2000` | `wallet_banned` | Wallet temporarily banned for insufficient gas |
| `2001` | `insufficient_gas` | Wallet has no gas tokens |
| `2002` | `insufficient_balance` | Not enough token balance |
| `2003` | `insufficient_allowance` | Token not approved for spending |
| `2004` | `slippage_exceeded` | Price moved too much during execution |
| `2005` | `call_exception` | Transaction will revert (generic) |
| `2006` | `transaction_reverted` | On-chain execution failed |
| `2007` | `rpc_error` | RPC provider temporary error |
| `2008` | `gas_estimation_failed` | Cannot estimate gas for transaction |
| `2009` | `invalid_amount` | Trade amount invalid or exceeds balance |
| `2010` | `approve_failed` | Token approval failed |
| `2011` | `check_allowance_failed` | Failed to check token allowance |

#### **Admin Errors (3000-3999)**
| Code | Error Type | Description |
|------|-----------|-------------|
| `3001` | `create_wallet_failed` | Failed to create new wallet |
| `3002` | `create_pool_failed` | Failed to create pool |
| `3003` | `get_pool_failed` | Failed to fetch pool data |
| `3004` | `get_summary_failed` | Failed to get pool summary |
| `3005` | `get_wallet_failed` | Failed to get wallet address |
| `3006` | `get_composition_failed` | Failed to get pool composition |
| `3007` | `get_manager_fee_failed` | Failed to fetch manager fee |
| `3008` | `mint_manager_fee_failed` | Failed to mint manager fee |
| `3009` | `change_assets_failed` | Failed to change pool assets |
| `3010` | `set_trader_failed` | Failed to set trader for pool |

#### **Investment Errors (4000-4999)**
| Code | Error Type | Description |
|------|-----------|-------------|
| `4001` | `approve_deposit_failed` | Failed to approve deposit |
| `4002` | `deposit_failed` | Failed to deposit into pool |

#### **Lending Errors (5000-5999)**
| Code | Error Type | Description |
|------|-----------|-------------|
| `5001` | `borrow_failed` | Failed to borrow assets |
| `5002` | `repay_failed` | Failed to repay borrowed assets |
| `5003` | `lend_failed` | Failed to lend assets |
| `5004` | `unlend_failed` | Failed to withdraw lent assets |

### **Error Flow: Express → Gateway → User**

```
Express (port 8000)
  ↓ Returns: {
       status: "fail",
       status_code: 2001,
       message: "...",
       error_type: "..."
     }
Gateway (port 8003)  
  ↓ Receives response
  ↓ Parses: fromJSON(response_content)
  ↓ Returns: AS-IS (no modification)
User
  ↓ Gets exact Express response
```

**Key Points**:
- ✅ Gateway passes Express errors through **unchanged**
- ✅ Users get structured errors with numeric codes
- ✅ Gateway's own validation errors use codes `1000-1999`
- ✅ Express execution errors use codes `2000-5999`
- ✅ Both systems now fully compatible

### **Current Error Types** (Maintained for backward compatibility)

The Express API currently uses **descriptive error types** but lacks numeric codes. This should be aligned with Gateway's system.

| Error Type | Description | HTTP Status | Should Be Code |
|-----------|-------------|-------------|----------------|
| `wallet_banned` | Wallet temporarily banned for insufficient gas | 429 | Need code |
| `insufficient_gas` | Wallet has no gas tokens | 400 | Need code |
| `insufficient_balance` | Not enough token balance | 400 | Need code |
| `insufficient_allowance` | Token not approved for spending | 400 | Need code |
| `slippage_exceeded` | Price moved too much | 400 | Need code |
| `call_exception` | Transaction will revert | 400 | Need code |
| `transaction_reverted` | On-chain execution failed | 400 | Need code |
| `rpc_error` | RPC provider temporary error | 503 | Need code |

### **Current Error Response Format**

```typescript
// Example: Insufficient gas
res.status(400).send({ 
  status: "fail", 
  msg: `Insufficient gas in wallet ${walletAddr}. This wallet has been temporarily banned for 15 minutes.`,
  error_type: "insufficient_gas",
  wallet_address: walletAddr,
  ban_duration_minutes: 15
});
```

### **⚠️ NEEDS IMPROVEMENT**: Standardize to Match Gateway

**Proposed new format** (align with Gateway):

```typescript
res.status(400).send({
  status: "fail",
  status_code: 2001,  // 2000-2999 range for Express errors
  message: "Insufficient gas in wallet",
  error_type: "insufficient_gas",
  details: {
    wallet_address: walletAddr,
    ban_duration_minutes: 15
  }
});
```

### **Proposed Express Error Codes** (2000-2999 range)

| Code | Error Type | Description |
|------|-----------|-------------|
| `2000` | `WALLET_BANNED` | Wallet temporarily banned for insufficient gas |
| `2001` | `INSUFFICIENT_GAS` | Wallet has no gas tokens |
| `2002` | `INSUFFICIENT_BALANCE` | Not enough token balance |
| `2003` | `INSUFFICIENT_ALLOWANCE` | Token not approved for spending |
| `2004` | `SLIPPAGE_EXCEEDED` | Price moved too much during execution |
| `2005` | `CALL_EXCEPTION` | Transaction will revert (generic) |
| `2006` | `TRANSACTION_REVERTED` | On-chain execution failed |
| `2007` | `RPC_ERROR` | RPC provider temporary error |
| `2008` | `GAS_ESTIMATION_FAILED` | Cannot estimate gas for transaction |
| `2009` | `INVALID_AMOUNT` | Trade amount invalid or exceeds balance |
| `2010` | `MISSING_PARAMETER` | Required parameter not provided |

### **Error Detection Logic** (Current Implementation)

```typescript
// trade.ts error handler
catch (err) {
  const errorObj = err as any;
  const message = (err instanceof Error) ? err.message : JSON.stringify(err);
  const errorLower = message.toLowerCase();
  
  // 1. CALL_EXCEPTION - transaction will revert
  if (errorObj?.code === 'CALL_EXCEPTION') {
    if (errorLower.includes('insufficient allowance')) {
      res.status(400).send({ 
        status: "fail", 
        msg: "Insufficient token allowance",
        error_type: "insufficient_allowance"
      });
    } else if (errorLower.includes('slippage')) {
      res.status(400).send({ 
        status: "fail", 
        msg: "Slippage tolerance exceeded",
        error_type: "slippage_exceeded"
      });
    }
  }
  
  // 2. Insufficient gas detection
  if (errorLower.includes('insufficient funds') && 
      (errorLower.includes('gas') || errorLower.includes('intrinsic transaction cost'))) {
    const walletAddr = errorObj?.transaction?.from || 'unknown';
    await banWalletForInsufficientGas(walletAddr);
    
    res.status(400).send({ 
      status: "fail", 
      msg: `Insufficient gas in wallet ${walletAddr}`,
      error_type: "insufficient_gas",
      wallet_address: walletAddr,
      ban_duration_minutes: 15
    });
  }
  
  // 3. RPC provider errors (retryable)
  if (errorObj?.code === 'SERVER_ERROR' || errorObj?.status === 500) {
    res.status(503).send({ 
      status: "fail", 
      msg: "RPC provider error. Please retry.",
      error_type: "rpc_error",
      retryable: true
    });
  }
  
  // 4. Generic fallback
  res.status(400).send({ status: "fail", msg: message });
}
```

### **Auto-Approval System**

When allowance errors are detected, Express **automatically approves** tokens:

```typescript
// Detect allowance issue during gas estimation
if (errorMsg.includes('allowance')) {
  console.log(`🔑 Allowance issue detected. Attempting auto-approve...`);
  
  const approveSuccess = await autoApproveToken(
    network, poolAddress, assetAddress, platform, apiKey, provider, key
  );
  
  if (approveSuccess) {
    // Retry the trade after approval
    estimatedGas = await pool.trade(...);
  } else {
    throw new Error('Auto-approve failed. Please approve manually.');
  }
}
```

### **Wallet Banning System** (Redis)

Wallets without gas are **temporarily banned** for 15 minutes:

```typescript
// Ban function
async function banWalletForInsufficientGas(walletAddress: string) {
  const redis = await getRedis();
  const banKey = `wallet_ban:insufficient_gas:${walletAddress.toLowerCase()}`;
  await redis.setEx(banKey, 900, Date.now().toString()); // 15 minutes
  console.log(`⛔ Wallet ${walletAddress} banned for 15 minutes`);
}

// Check before trade
const isBanned = await isWalletBanned(walletAddress);
if (isBanned) {
  res.status(429).send({
    status: "fail",
    msg: "Wallet temporarily banned due to insufficient gas",
    error_type: "wallet_banned",
    wallet_address: walletAddress
  });
  return;
}
```

---

## Database Architecture

### **MySQL Database: `infinitetrading`**

**Connection Details**:
- Host: `localhost`
- Port: `3306`
- User: `richard_clare`
- Database: `infinitetrading`

**Key Tables**:
- `api_keys` - API key management
- `gas_wallets` - Gas wallet tracking
- `pools` - Pool information
- `transactions` - Transaction history
- `bots` - Strategy bot configurations
- `allocations` - Portfolio allocations
- `yields` - Historical yield data

**Access Pattern**:
- **R API**: Direct MySQL access via `RMariaDB` package
- **Express API**: Indirect via Gateway (should add direct access for performance)

### **Redis Cache**

**Purpose**:
- Rate limiting (Gateway)
- Wallet ban tracking (Express)
- Session management (future)

**Key Patterns**:
- `wallet_ban:insufficient_gas:{address}` - TTL 900s (15 min)
- `rate_limit:{ip}` - Request tracking per IP

---

## Deployment Workflow

### **Express API Deployment**

```bash
# 1. Local development
cd /Users/richardclare/infinite-trading-api/express
npm run build

# 2. Deploy to EC2
rsync -avz --exclude 'node_modules' --exclude 'logs' \
  -e "ssh -i ~/.ssh/macbook.pem" \
  ./ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading_api/express/

# 3. Restart PM2
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "cd /home/ubuntu/infinitetrading_api/express && pm2 restart ecosystem.config.js"
```

### **Gateway Deployment**

```bash
# 1. Deploy files
rsync -avz -e "ssh -i ~/.ssh/macbook.pem" \
  ./gateway/ \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading/src/api/gateway/

# 2. Restart gateway
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "screen -X -S gateway quit && screen -dmS gateway -h 1000 bash -c 'cd ~/infinitetrading/src/api/gateway && ./infinite.sh gateway.R'"

# 3. Reload Nginx if endpoints changed
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com \
  "sudo nginx -s reload"
```

### **Full System Restart**

```bash
# SSH into server
ssh -i ~/.ssh/macbook.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Run startup script
./startup.sh
```

---

## 🚨 Critical Rules for AI Agents

### **DO:**
- ✅ Always use proper error codes (Gateway: 1000-1999, Express: 2000-2999)
- ✅ Log concisely with structured formats
- ✅ Check wallet bans before trading
- ✅ Use Redis for temporary bans
- ✅ Auto-approve tokens when allowance errors occur
- ✅ Proxy Express calls through Gateway for validation
- ✅ Use RetryProvider for RPC calls (3 retries × 3 providers)
- ✅ Test locally before deploying
- ✅ Build TypeScript before deploying (`npm run build`)
- ✅ Restart PM2 after Express deployment
- ✅ Restart screen sessions after Gateway deployment

### **DON'T:**
- ❌ Don't edit `/etc/nginx/snippets/itp_endpoints.conf` manually (auto-generated)
- ❌ Don't deploy without building first
- ❌ Don't use `console.log` for objects (use structured single-line logs)
- ❌ Don't add newlines (`\n`) in logs (PM2 doesn't render them)
- ❌ Don't return errors without `status_code` fields
- ❌ Don't retry non-retryable errors (allowance, balance, slippage)
- ❌ Don't execute trades on banned wallets
- ❌ Don't forget to update Nginx when adding Gateway endpoints
- ❌ Don't use raw MySQL in Express (proxy through Gateway or use proper connection pool)

---

## 📝 TODO: Improvements Needed

1. **Standardize Express error codes** to match Gateway format (2000-2999 range)
2. **Add `status_code` field** to all Express error responses
3. **Create error code documentation** for API consumers
4. **Add direct MySQL connection** to Express (avoid Gateway proxy for performance)
5. **Implement structured logging** across all services (JSON format)
6. **Add health check endpoints** (`/health`, `/status`)
7. **Containerize all services** (Docker migration plan)
8. **Add metrics/monitoring** (Prometheus + Grafana)

---

## Questions? Need Clarification?

This document should be updated whenever:
- New endpoints are added
- Error codes change
- Deployment process changes
- Infrastructure changes (new services, ports, etc.)

**Last Updated**: 2026-02-10
**Maintained By**: AI Agent + etherpilled
