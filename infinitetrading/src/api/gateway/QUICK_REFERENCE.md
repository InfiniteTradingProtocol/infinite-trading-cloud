# Quick Reference: LLM Introspection Endpoint

## Endpoint URL
```
GET https://api.infinitetrading.io/llmIntrospect
```

## Quick Test
```bash
curl https://api.infinitetrading.io/llmIntrospect | jq '.api_info'
```

## Response Sections

| Section | Description | Example Access |
|---------|-------------|----------------|
| `api_info` | API metadata | `response.api_info.title` |
| `categories` | Functional categories | `response.categories` |
| `endpoints` | All endpoint docs | `response.endpoints` |
| `networks` | Supported blockchains | `response.networks` |
| `protocols` | DeFi protocols | `response.protocols` |
| `platforms` | Trading platforms | `response.platforms` |
| `usage_notes` | Best practices | `response.usage_notes` |
| `error_codes` | Error reference | `response.error_codes` |

## Categories (11)

1. **Asset Management** - Approve assets for trading
2. **Trading** - Execute vault trades
3. **Automation** - Configure trading bots
4. **Market Data** - Candles and ticks
5. **Portfolio** - Pool composition
6. **Wallet** - Gas balance management
7. **Blockchain** - Contract interactions
8. **DeFi Lending** - Aave V3 operations
9. **Authentication** - API key management
10. **Pool Management** - Fee minting
11. **CEX Integration** - Exchange integration

## Common Queries

### Find endpoints by category
```javascript
const tradingEndpoints = response.endpoints.filter(
  e => e.category === 'Trading'
);
```

### Get endpoint parameters
```javascript
const endpoint = response.endpoints.find(e => e.name === 'vaultTrade');
const required = endpoint.parameters.filter(p => p.required);
```

### Check supported networks
```javascript
console.log(response.networks);
// ['Optimism', 'Base', 'Arbitrum', 'Polygon']
```

## Key Endpoints Documented

### Trading
- `vaultTrade` - Execute trades within vault

### Automation  
- `setBot` - Configure trading bot
- `deleteBot` - Remove trading bot

### Market Data
- `getCandles` - Historical price data
- `getTicks` - Real-time ticks

### DeFi
- `aaveV3` - Full Aave V3 integration
  - `/lend` - Supply assets
  - `/unlend` - Withdraw assets
  - `/borrow` - Borrow against collateral
  - `/repay` - Repay borrowed assets

### Asset Management
- `approve` - Approve assets for trading

### CEX Integration
- `registerCEXSubaccount` - Register exchange account
- `setCEXSide` - Set trading side (long/short)
- `getCEXSide` - Get current side
- `deleteCEXBot` - Delete CEX bot
- `deactivateCEXBot` - Deactivate CEX bot
- `deleteCEXSubaccount` - Remove subaccount

## Parameter Types

- `string` - Text values
- `number` - Numeric values
- `boolean` - true/false

## Common Parameters

| Parameter | Description | Required |
|-----------|-------------|----------|
| `apiKey` | Authentication key | ✅ |
| `network` | Blockchain network | ✅ |
| `protocol` | DeFi protocol | ✅ |
| `pool` | Pool address | ✅ |
| `asset` | Token symbol/address | Varies |
| `share` | Percentage (1-100) | ❌ |
| `amount` | Fixed amount | ❌ |
| `slippage` | Slippage tolerance | ❌ |

## Error Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 400 | Bad request |
| 401 | Invalid API key |
| 429 | Rate limit exceeded |
| 500 | Server error |
| 1007 | Invalid share parameter |

## Rate Limits
- **600 requests/minute per IP**
- Applies to all endpoints including `/llmIntrospect`

## Files Location

```
/infinitetrading/src/api/gateway/
├── endpoints/
│   ├── llmIntrospect.R                    # Main endpoint
│   ├── LLM_INTROSPECT_README.md           # Full documentation
│   ├── LLM_INTEGRATION_EXAMPLES.md        # Usage examples
│   └── test_llm_introspect.sh            # Test script
├── gateway.R                              # Gateway router
└── IMPLEMENTATION_SUMMARY.md              # Implementation details
```

## Testing

### Run Test Script
```bash
cd infinitetrading/src/api/gateway/endpoints
./test_llm_introspect.sh
```

### Manual Test
```bash
# Get all endpoints
curl http://localhost:8003/llmIntrospect | jq '.endpoints[].name'

# Get specific endpoint
curl http://localhost:8003/llmIntrospect | jq '.endpoints[] | select(.name == "vaultTrade")'

# List categories
curl http://localhost:8003/llmIntrospect | jq '.categories[].name'
```

## LLM Integration Pattern

```javascript
// 1. Fetch docs
const docs = await fetch(API_URL + '/llmIntrospect').then(r => r.json());

// 2. Find endpoint
const endpoint = docs.endpoints.find(e => e.name === 'vaultTrade');

// 3. Validate params
const required = endpoint.parameters.filter(p => p.required);

// 4. Build request
const params = { /* ... */ };

// 5. Execute
const result = await fetch(API_URL + endpoint.path, {
  method: endpoint.method,
  body: JSON.stringify(params)
});
```

## Hidden Endpoints (Not Included)

These are excluded from introspection:
- `/createGasWallet`
- `/linkGasWallet` / `/unlinkGasWallet`
- `/getAllBots` / `/getAllGasBalance`
- `/getEstimatedAnualYield` / `/getTotalYield` / `/getAllYields`
- `/getGasWalletPools`
- `/associateGasWallet` / `/deassociateGasWallet`
- `/getAssociatedGasWallets`
- `/setCEXStrategy`

## Support

- **Documentation**: See `LLM_INTROSPECT_README.md`
- **Examples**: See `LLM_INTEGRATION_EXAMPLES.md`
- **Implementation**: See `IMPLEMENTATION_SUMMARY.md`
- **API Portal**: https://www.infinitetrading.io/docs

---

**Version**: 1.0.0 | **Date**: April 16, 2026
