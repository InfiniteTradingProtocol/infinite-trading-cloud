# Automated Vault Deployment & Strategy Launch Plan

## Overview
Create an automated endpoint that deploys a new vault, links a gas wallet as trader, and launches a PM2 strategy process - all in one operation.

## Current System Analysis

### Existing Components

#### 1. **Frontend Vault Configuration** (`infinite-trading-frontend/app/utils/vaultConfig.ts`)
- Defines vault types, asset configurations per chain
- Has vault deployment configurations
- Contains EasySwapper addresses for each network

#### 2. **Express API Endpoints** (`infinitetrading_api/express/src/requests/admin.ts`)
- `/createPool` - Deploys a new dHedge pool/vault
  - Parameters: managerName, poolName, symbol, supportedAssets, fee
  - Supports both manager wallet and apiKey authentication
- `/setTrader` - Authorizes a wallet as trader on a pool
  - Sets trader permissions on the pool contract

#### 3. **Gateway API Endpoints** (`infinitetrading/src/api/gateway/endpoints/`)
- `/createGasWallet` - Creates new Ethereum wallet, returns address/privateKey/apiKey
- `/linkGasWallet` - Associates gas wallet with a pool (requires trader authorization first)
- `/unlinkGasWallet` - Removes gas wallet association

#### 4. **Strategy System** (`infinitetrading/src/strategies/`)
- Strategy scripts (e.g., `crossOvers.R`, `superTrend.R`, `ITPBot.R`)
- Each strategy has:
  - Network, protocol, pool configurations
  - Trading pairs and parameters
  - Calls `itp_api(endpoint = "setBot", ...)` to set trading signals

#### 5. **PM2 Ecosystem** (`infinitetrading_api/ecosystem.config.js`)
- Manages all services including strategy processes
- Strategy example:
  ```javascript
  {
    name: 'strategy-crossovers',
    script: 'Rscript',
    args: 'strategies/crossOvers.R',
    cwd: '/home/ubuntu/infinitetrading/src'
  }
  ```

## Proposed Solution

### New Endpoint: `/deployBotVault`

**Location**: `infinitetrading_api/express/src/requests/admin.ts`

**Method**: `POST`

**Parameters**:
```typescript
{
  apiKey: string;                // REQUIRED: API key of gas wallet (trader)
  network: Network;              // REQUIRED: Network to deploy on (e.g., "base", "optimism", "polygon")
  description: string;           // REQUIRED: Vault description/name
  
  // Optional: Advanced Configuration (with sensible defaults)
  protocol?: string;             // Default: "dhedge"
  symbol?: string;               // Default: Auto-generated
  supportedAssets?: string[];    // Default: Network-specific assets
  fee?: number;                  // Default: 200 (2%)
  provider?: string;             // Default: "infura"
  providerKey?: string;          // Default: from env
}
```

### Implementation Steps

The endpoint executes **3 critical steps** in sequence. Each step tracks its own status, and failure at any step prevents subsequent steps from executing.

#### Step 1: Create Vault/Pool
```typescript
const step1 = { status: 'pending', txHash: null, error: null };

try {
  // Derive trader address from API key
  const traderAddress = await getAddressFromApiKey(apiKey);
  
  // Get required network parameter
  const network = req.body.network; // REQUIRED
  
  // Set defaults for optional parameters
  const protocol = req.body.protocol || 'dhedge';
  const symbol = req.body.symbol || `BOT-${Date.now()}`;
  const supportedAssets = req.body.supportedAssets || getDefaultAssets(network);
  const fee = req.body.fee || 200;
  
  // Initialize dHedge SDK
  const dHedge = await dhedgev2(network, apiKey, provider, providerKey);
  
  // Create the pool
  const pool = await dHedge.createPool(
    traderAddress,        // managerName (use trader address)
    description,          // poolName
    symbol,
    supportedAssets,
    fee
  );
  
  const poolAddress = pool.address;
  step1.status = 'success';
  step1.txHash = pool.deployTransaction?.hash;
  
} catch (error) {
  step1.status = 'failed';
  step1.error = error.message;
  // Return early - don't execute step 2 or 3
  return res.status(400).send({
    status: 'failed',
    step1,
    step2: { status: 'skipped', reason: 'Step 1 failed' },
    step3: { status: 'skipped', reason: 'Step 1 failed' }
  });
}
```

#### Step 2: Set Trader Authorization
```typescript
const step2 = { status: 'pending', txHash: null, error: null };

try {
  // Load the pool
  const dHedge = await dhedgev2(network, apiKey, provider, providerKey);
  const pool = await dHedge.loadPool(poolAddress);
  
  // Set trader permissions
  const tx = await pool.setTrader(traderAddress);
  await tx.wait();
  
  step2.status = 'success';
  step2.txHash = tx.hash;
  
} catch (error) {
  step2.status = 'failed';
  step2.error = error.message;
  // Return early - don't execute step 3
  return res.status(400).send({
    status: 'failed',
    poolAddress,
    step1,
    step2,
    step3: { status: 'skipped', reason: 'Step 2 failed' }
  });
}
```

#### Step 3: Link Gas Wallet to Vault
```typescript
const step3 = { status: 'pending', response: null, error: null };

try {
  // Call linkGasWallet through gateway
  const linkResponse = await fetch(
    `http://localhost:8003/linkGasWallet?` +
    `network=${network}&protocol=${protocol}&` +
    `pool=${poolAddress}&apiKey=${apiKey}`,
    { method: 'POST' }
  );
  
  const linkData = await linkResponse.json();
  
  if (linkData.status === 'success') {
    step3.status = 'success';
    step3.response = linkData;
  } else {
    step3.status = 'failed';
    step3.error = linkData.message || 'Failed to link gas wallet';
  }
  
} catch (error) {
  step3.status = 'failed';
  step3.error = error.message;
}

// Final response based on all steps
if (step3.status === 'success') {
  return res.status(200).send({
    status: 'success',
    poolAddress,
    step1,
    step2,
    step3
  });
} else {
  return res.status(400).send({
    status: 'failed',
    poolAddress,
    step1,
    step2,
    step3
  });
}
```

### Strategy Script Template

**Template**: `infinitetrading/src/strategies/templates/template_strategy.R`

```r
# Auto-generated strategy for pool <%= poolAddress %>
source("~/infinitetrading/src/strategies/main.R")
library(TTR)

# Configuration
network <- "<%= network %>"
protocol <- "<%= protocol %>"
pool <- "<%= poolAddress %>"
pair <- "<%= pair %>"
candles_pair <- "<%= candlesPair %>"
timeframe <- "<%= timeframe %>"
slippage <- <%= slippage %>
max_usd <- <%= maxUsd %>
threshold <- <%= threshold %>
share <- <%= share %>
platform <- "<%= platform %>"
apiKey <- "<%= apiKey %>"

# Strategy logic
last_side <- "hold"

while (TRUE) {
  tryCatch({
    candles <- get_candles_with_retry(pair = candles_pair, numcandles = 300, timeframe = timeframe)
    
    # <%= strategyType %> strategy logic here
    # ...
    
    if (last_side != side) {
      itp_api(endpoint = "setBot", params = list(
        apiKey = apiKey,
        protocol = protocol,
        network = network,
        pool = pool,
        pair = pair,
        side = side,
        max_usd = max_usd,
        slippage = slippage,
        threshold = threshold,
        share = share,
        platform = platform
      ))
      last_side <- side
    }
  }, error = function(e) {
    cat(paste0("Error: ", e$message, "\n"))
  })
  
  Sys.sleep(60 * 15)  # 15 minute interval
}
```

### Response Format

#### Success Response (All 3 Steps Completed)
```typescript
{
  status: "success",
  poolAddress: "0x1234...",
  step1: {
    status: "success",
    txHash: "0xabc123...",
    error: null
  },
  step2: {
    status: "success",
    txHash: "0xdef456...",
    error: null
  },
  step3: {
    status: "success",
    response: {
      status: "success",
      message: "Gas wallet linked successfully"
    },
    error: null
  }
}
```

#### Failure Response Examples

**Step 1 Fails:**
```typescript
{
  status: "failed",
  step1: {
    status: "failed",
    txHash: null,
    error: "Insufficient funds for gas"
  },
  step2: {
    status: "skipped",
    reason: "Step 1 failed"
  },
  step3: {
    status: "skipped",
    reason: "Step 1 failed"
  }
}
```

**Step 2 Fails:**
```typescript
{
  status: "failed",
  poolAddress: "0x1234...",
  step1: {
    status: "success",
    txHash: "0xabc123...",
    error: null
  },
  step2: {
    status: "failed",
    txHash: null,
    error: "Trader already set"
  },
  step3: {
    status: "skipped",
    reason: "Step 2 failed"
  }
}
```

**Step 3 Fails:**
```typescript
{
  status: "failed",
  poolAddress: "0x1234...",
  step1: {
    status: "success",
    txHash: "0xabc123...",
    error: null
  },
  step2: {
    status: "success",
    txHash: "0xdef456...",
    error: null
  },
  step3: {
    status: "failed",
    response: null,
    error: "API key not valid for this pool"
  }
}
```

## Security Considerations

1. **API Key Handling**
   - API keys are provided by user, not generated
   - Never store API keys in database
   - User must manage their own gas wallet API keys securely
   - Only store trader_address as reference

2. **Gas Wallet Requirements**
   - User must create gas wallet beforehand using `/createGasWallet`
   - Gas wallet must have sufficient gas on target network
   - User is responsible for securing private keys

3. **Access Control**
   - Require authentication for this endpoint
   - Rate limit to prevent abuse
   - Audit log all vault deployments

## Database Schema Addition

```sql
CREATE TABLE IF NOT EXISTS deployed_vaults (
  id INT AUTO_INCREMENT PRIMARY KEY,
  pool_address VARCHAR(42) NOT NULL UNIQUE,
  network VARCHAR(20) NOT NULL,
  protocol VARCHAR(20) NOT NULL,
  trader_address VARCHAR(42) NOT NULL,
  strategy_type VARCHAR(50) NOT NULL,
  strategy_params JSON,
  pm2_process_name VARCHAR(100) NOT NULL,
  script_path VARCHAR(255) NOT NULL,
  pool_creation_tx VARCHAR(66),
  trader_auth_tx VARCHAR(66),
  status ENUM('active', 'paused', 'stopped') DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_pool_address (pool_address),
  INDEX idx_network (network),
  INDEX idx_trader_address (trader_address),
  INDEX idx_status (status)
);
```

## Additional Helper Endpoints

### `/stopStrategy`
Stop a running strategy process
```typescript
POST /stopStrategy
{
  poolAddress: string;
}
```

### `/restartStrategy`
Restart a stopped strategy
```typescript
POST /restartStrategy
{
  poolAddress: string;
}
```

### `/updateStrategyParams`
Modify strategy parameters without redeployment
```typescript
POST /updateStrategyParams
{
  poolAddress: string;
  strategyParams: object;
}
```

### `/getVaultStatus`
Get current status of deployed vault and strategy
```typescript
GET /getVaultStatus?pool=<address>
Response: {
  poolInfo: {...},
  strategyStatus: "running" | "stopped" | "errored",
  lastSignal: {...},
  performance: {...}
}
```

## Testing Strategy

1. **Unit Tests**
   - Test each step independently
   - Mock external API calls
   - Validate error handling

2. **Integration Tests**
   - Deploy test vault on testnet
   - Verify trader authorization
   - Confirm PM2 process starts
   - Test strategy execution

3. **Manual Testing Checklist**
   - [ ] Vault deploys successfully
   - [ ] Trader wallet is authorized
   - [ ] Gas wallet is linked
   - [ ] Strategy script is created
   - [ ] PM2 process starts and runs
   - [ ] Trading signals are sent correctly
   - [ ] Error handling works as expected

## Rollout Plan

1. **Phase 1**: Implement core endpoint (Steps 1-4)
2. **Phase 2**: Add strategy generation and PM2 integration (Steps 5-6)
3. **Phase 3**: Add database tracking (Step 7)
4. **Phase 4**: Implement helper endpoints
5. **Phase 5**: Add monitoring and alerting
6. **Phase 6**: Production deployment with limited access
7. **Phase 7**: Full rollout with documentation

## Helper Function: Get Address from API Key

This function needs to be implemented to derive the wallet address from an API key:

```typescript
async function getAddressFromApiKey(apiKey: string): Promise<string> {
  // Option 1: Call gateway endpoint
  const response = await fetch(
    `http://localhost:8003/getWalletFromApiKey?apiKey=${apiKey}`
  );
  const data = await response.json();
  
  if (data.status === 'success') {
    return data.address;
  }
  
  // Option 2: Derive from API key if it's deterministic
  // (depends on how API keys are generated)
  
  throw new Error('Could not derive address from API key');
}
```

## Open Questions

1. **Default Assets**: What default assets should be supported for each network?
2. **Fee Structure**: Should the default 2% fee be configurable per deployment?
3. **Gateway Endpoint**: Does `/getWalletFromApiKey` exist or need to be created?
4. **Error Recovery**: Should we provide a way to retry failed steps?
5. **Testnet Support**: Should this work on testnets for testing?

## Simplified Implementation Plan

### Phase 1: Core 3-Step Deployment (Immediate)
1. Create `/deployBotVault` endpoint in `admin.ts`
2. Implement helper function `getAddressFromApiKey`
3. Add 3-step sequential execution with status tracking
4. Add proper error handling and rollback prevention
5. Test on testnet

### Phase 2: Enhancement (Later)
1. Add database tracking of deployed vaults
2. Create helper endpoints (stop/restart vault)
3. Add PM2 strategy generation and launch
4. Implement monitoring and alerts

## Example Usage

```bash
# Simple deployment with required parameters
curl -X POST http://localhost:8000/deployBotVault \
  -H "Content-Type: application/json" \
  -d '{
    "apiKey": "your-gas-wallet-api-key",
    "network": "base",
    "description": "My First Trading Vault"
  }'

# Advanced deployment with custom settings
curl -X POST http://localhost:8000/deployBotVault \
  -H "Content-Type: application/json" \
  -d '{
    "apiKey": "your-gas-wallet-api-key",
    "network": "optimism",
    "description": "Custom ETH Vault",
    "symbol": "ETH-VAULT",
    "fee": 100,
    "supportedAssets": ["0x4200000000000000000000000000000000000006", "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"]
  }'
```

---

**Status**: Draft - Ready for Discussion
**Author**: GitHub Copilot
**Date**: March 23, 2026
