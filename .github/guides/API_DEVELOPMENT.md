# API Development Guide

## Local Setup

```bash
cd infinitetrading_api/express
npm install
npm run build
npm run start:watch  # Development mode with hot reload
```

## Project Structure

```
src/
├── requests/              # API endpoint handlers
│   ├── trade.ts          # Main trading endpoints
│   ├── trade-fallback.ts # DEX fallback logic
│   ├── trade-odosv2.ts   # ODOS integration
│   ├── admin.ts          # Admin endpoints
│   ├── invest.ts         # Investment operations
│   └── lending.ts        # Lending/borrowing
│
├── utils/                # Utility functions
│   ├── vault-guard-cache.ts      # Guard caching (Redis)
│   ├── vault-guard-checker.ts    # Guard validation
│   ├── dex-approve.ts            # Approval management
│   ├── dex-ban.ts                # DEX banning logic
│   ├── pool.ts                   # Pool operations
│   ├── ERC20.ts                  # Token interactions
│   ├── RetryProvider.ts          # RPC failover
│   ├── txOptions.ts              # Transaction builders
│   └── redis.ts                  # Redis utilities
│
├── lib/                  # Core libraries
│   └── redis.ts         # Redis connection
│
├── index.ts             # Main server (port 8000)
├── index_test.ts        # Test server (port 8001)
├── dhedge.ts            # dHEDGE SDK setup
├── wallet.ts            # Wallet management
├── rpc.ts               # RPC providers
└── txFees.ts            # Fee calculation
```

## Adding a New Endpoint

1. **Create handler in `src/requests/`**

```typescript
// src/requests/myfeature.ts
import { Request, Response } from "express";
import { Network } from "@dhedge/v2-sdk";

export async function myFeatureHandler(req: Request, res: Response) {
    try {
        const { network, param1 } = req.query;
        
        // Validation
        if (!network) {
            return res.status(400).json({ error: "Network required" });
        }
        
        // Your logic here
        const result = await doSomething(param1 as string);
        
        return res.json({ success: true, data: result });
    } catch (error) {
        console.error("Error in myFeature:", error);
        return res.status(500).json({ error: error.message });
    }
}
```

2. **Register route in `src/index.ts`**

```typescript
import { myFeatureHandler } from "./requests/myfeature";

app.get("/myfeature", myFeatureHandler);
```

3. **Test locally**

```bash
npm run start:watch
curl "http://localhost:8000/myfeature?network=polygon&param1=value"
```

## Working with Redis Cache

### Adding a New Cache

```typescript
import { getRedis } from "../lib/redis";

const CACHE_TTL = 24 * 60 * 60; // 24 hours
const CACHE_KEY = "myfeature:data";

async function getCachedData() {
    try {
        const redis = await getRedis();
        const cached = await redis.get(CACHE_KEY);
        
        if (cached) {
            console.log("✅ Using cached data");
            return JSON.parse(cached);
        }
    } catch (error) {
        console.warn("Cache check failed:", error);
    }
    
    // Cache miss - fetch data
    const data = await fetchData();
    
    // Store in cache
    try {
        const redis = await getRedis();
        await redis.setEx(CACHE_KEY, CACHE_TTL, JSON.stringify(data));
        console.log("💾 Data cached");
    } catch (error) {
        console.warn("Failed to cache:", error);
    }
    
    return data;
}
```

## DEX Integration

### Adding Support for a New DEX

1. **Add DEX to fallback chain** in `trade-fallback.ts`:

```typescript
const DEX_FALLBACKS: Record<string, Dapp[]> = {
    [Network.OPTIMISM]: [
        "odos" as Dapp,
        "1inch" as Dapp,
        "mynewdex" as Dapp,  // Add here
        "kyberswap" as Dapp
    ],
};
```

2. **Add DEX router address** in `vault-guard-checker.ts`:

```typescript
const DEX_ROUTER_ADDRESSES: Record<string, Record<string, string>> = {
    [Network.OPTIMISM]: {
        "odos": "0xCa423977156BB05b13A2BA3b76Bc5419E2fE9680",
        "mynewdex": "0xYourRouterAddress",  // Add here
    },
};
```

3. **Implement trade logic** if custom integration needed

## Error Handling Best Practices

```typescript
try {
    // Your code
} catch (error: any) {
    // Log detailed error
    console.error("Detailed error context:", {
        message: error?.message,
        reason: error?.reason,
        code: error?.code,
        transaction: error?.transaction
    });
    
    // Return user-friendly error
    return res.status(500).json({ 
        error: "User-friendly message",
        details: error?.message 
    });
}
```

## Testing

### Unit Tests (Future)

```typescript
// tests/myfeature.test.ts
import { myFeatureHandler } from "../src/requests/myfeature";

describe("MyFeature", () => {
    it("should handle valid input", async () => {
        // Test implementation
    });
});
```

### Manual Testing

```bash
# Test trade endpoint
curl "http://localhost:8000/trade?network=optimism&pool=0x..."

# Test with different parameters
curl "http://localhost:8000/trade?network=base&pool=0x...&slippage=1"

# Check logs
tail -f logs/api-*.log
```

## Common Patterns

### Retry Logic

```typescript
import { createRetryProviderWithFailover } from "./utils/RetryProvider";

const providerUrls = getAllRpcProviders(network);
const provider = createRetryProviderWithFailover(providerUrls);
```

### Guard Validation

```typescript
import { filterWhitelistedDexs } from "./utils/vault-guard-checker";

const whitelistedDexs = await filterWhitelistedDexs(
    vaultAddress,
    ["odos", "1inch", "uniswapV3"],
    network
);
```

### Gas Estimation with Fallback

```typescript
import { tradeWithFallback } from "./requests/trade-fallback";

const gasEstimate = await tradeWithFallback({
    pool,
    network,
    primaryDapp: "odos",
    assetFrom,
    assetTo,
    amountIn,
    slippage,
    txOptions,
    estimateGasOnly: true
});
```

## Deployment Checklist

Before deploying API changes:

- [ ] TypeScript compiles without errors (`npx tsc --noEmit`)
- [ ] Local build succeeds (`npm run build`)
- [ ] Tested endpoint locally
- [ ] Checked logs for errors
- [ ] Updated documentation if needed
- [ ] Committed changes to git

Then deploy:

```bash
cd infinitetrading_api
./deploy-to-ec2.sh
```
