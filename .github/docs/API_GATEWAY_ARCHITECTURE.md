# API Gateway & Plumber Architecture Guide

## Overview

The Infinite Trading API has a 3-layer architecture:
1. **Gateway** (port 8003) - Nginx-accessible public entry point
2. **Plumber API** (port 8002) - R-based API layer for validation and routing
3. **Express API** (port 8000) - Node.js/TypeScript layer for blockchain interactions

## Key Learnings

### 1. Asset Parameter Handling

**CRITICAL**: Do NOT convert asset symbols to contract addresses in Gateway endpoints

**Problem**: The `/aaveV3/*` endpoints were converting assets using `get_contract(asset, network)` before forwarding to Plumber API. This caused double-conversion issues because Plumber API also calls `get_contract()`.

**Solution**: Gateway endpoints should pass asset symbols AS-IS. Only the final layer (Plumber API calling Express) should convert symbols to contract addresses.

```r
# ❌ WRONG - Gateway endpoint
asset_contract = get_contract(asset, network)
url <- paste0(pep, "lend?asset=", asset_contract, ...)

# ✅ CORRECT - Gateway endpoint  
url <- paste0(pep, "lend?asset=", asset, ...)
```

**Why**: 
- `get_contract()` looks up symbols in `coins.csv`
- If you pass a contract address as input, it returns `NULL` (not found)
- This breaks the entire flow

### 2. Endpoint Variable Naming

- `ep` = Express API (http://localhost:8000/)
- `pep` = Plumber API (http://localhost:8002/)

Gateway endpoints use `pep` to route to Plumber, which then uses `ep` to route to Express.

### 3. Redundant Endpoints Issue

**Status**: The `/lend`, `/borrow`, `/getBorrowed`, `/getSupplied` endpoints exist in TWO places:
- Main gateway: `/lend`, `/borrow`, etc.
- Sub-router: `/aaveV3/lend`, `/aaveV3/borrow`, etc.

**Behavior**: Both should work identically now that asset conversion is fixed.

**Recommendation**: Remove redundant `/aaveV3/*` endpoints OR remove main endpoints and keep only `/aaveV3/*` for clarity.

### 4. Approve Endpoint Requirements

The `/approve` endpoint has specific requirements:

**Query Parameters**:
- `apiKey` - API key for authentication
- `protocol` - e.g., "dhedge"
- `network` - e.g., "optimism"
- `pool` - Vault address
- `platform` - e.g., "aavev3", "uniswapv3", "odos"

**Body** (JSON):
- `asset` - Token symbol OR contract address

```bash
# ✅ CORRECT
curl -X POST "https://api.infinitetrading.io/approve?apiKey=xxx&protocol=dhedge&network=optimism&pool=0x...&platform=aavev3" \
  -H "Content-Type: application/json" \
  -d '{"asset": "USDC"}'

# ❌ WRONG - asset in query params
curl -X POST "https://api.infinitetrading.io/approve?asset=USDC&..."
```

### 5. Gas Wallet Requirements

**Critical**: Before ANY lending/trading operations, the vault's gas wallet MUST have sufficient ETH/MATIC for gas:

1. Create gas wallet via `/createGasWallet`
2. **Fund it with native gas token** (ETH on Optimism/Arbitrum/Base, MATIC on Polygon)
3. Link it to vault via `/linkGasWallet`
4. Set vault to allow gas wallet as "trader" on dHEDGE UI
5. Approve tokens via `/approve`
6. Then lend/trade

**Common Errors**:
- `execution reverted: ERC20: transfer amount exceeds allowance` → Token not approved
- `gas required exceeds allowance` → Insufficient gas in wallet
- `Router address not found for aavev3` → Platform not supported for approval (legacy error)

### 6. Nginx Configuration

After modifying gateway endpoints (`src/api/helpers/endpoints.R`), regenerate
nginx's public allowlist:

```bash
ssh ubuntu@ec2 "bash ~/infinitetrading/src/api/gateway/deploy.sh"
```

This is also done automatically by the top-level `deploy.sh` (step 5) on
every deployment, so the allowlist can't silently drift out of sync with
`endpoints.R` again.

This script:
1. Reads every endpoint name directly from `endpoints.R` (including anything
   in `hidden_endpoints` — that array only hides paths from R's own Swagger
   UI, it does NOT mean "not public"; nginx must still proxy those or they'd
   break for real callers)
2. Generates a single regex allowlist for nginx
3. Writes `/etc/nginx/snippets/itp_endpoints.conf`
4. Validates and reloads nginx

Do NOT use `deployNew.sh` in the same directory for this — it builds the
allowlist from R's live `/openapi.json` instead, which excludes
`hidden_endpoints` by construction and will silently break any endpoint R
hides from its own docs page (e.g. `getAllBots`, `associateGasWallet`,
`getAllYields`). It's kept only for manual reference/diffing.

All sub-router endpoints (e.g. `/aaveV3/lend`, `/compoundV3/lend`,
`/fluid/unlend`) are covered by the same single top-level regex block that
`deploy.sh` emits, matched against the full path `/prefix/action`.

### 7. Deployment Workflow

**For R/Plumber changes** (gateway, plumber-api):
```bash
# Edit files locally in infinitetrading/src/api/
# Commit and push to GitHub
ssh ubuntu@ec2
cd ~/infinitetrading
git pull
pm2 restart api-gateway  # or plumber-api
```

**For TypeScript/Express changes**:
```bash
cd infinitetrading_api/express
# Edit src/requests/*.ts files
scp -i ~/.ssh/macmini.pem src/requests/file.ts ubuntu@ec2:infinitetrading_api/express/src/requests/
ssh ubuntu@ec2 "cd infinitetrading_api/express && npm run build && pm2 restart infinitetrading-api"
```

**NEVER use `git pull` in `infinitetrading_api/express` on EC2** - that directory is not in git!

## File Locations

- Gateway endpoints: `infinitetrading/src/api/gateway/endpoints/*.R`
- Plumber API handlers: `infinitetrading/src/api/api.R`
- Express API routes: `infinitetrading_api/express/src/requests/*.ts`
- Helper functions: `infinitetrading/src/api/helpers/apiHelpers.R`
- Token contracts CSV: `infinitetrading/coins.csv`

## Testing AAVEv3 Endpoints

See `test_aavev3_getsupplied.sh` for comprehensive testing script.

Key test flow:
1. Check current supplied/borrowed amounts
2. (Skip approve - insufficient gas in test vault)
3. Attempt lend with share=100
4. Verify supplied amount increased

## API Pricing

All actions are priced in USD and converted to native token (ETH/MATIC) dynamically:

| Action | Price (USD) | Description |
|--------|-------------|-------------|
| `trade` | $0.10 | Standard trade execution |
| `approve` | $0.02 | Token approval |
| `lend` | **$0.05** | Lending operation (AAVEv3, etc) |
| `borrow` | **$0.05** | Borrow operation |
| `repay` | $0.05 | Repay loan |
| `cex_trade` | $0.10 | CEX trade execution |
| `deposit` | FREE | Pool deposit |
| `withdraw` | FREE | Pool withdrawal |
| `poolComposition` | FREE | Get pool composition |
| `claimRewards` | FREE | Claim rewards |
| `query` | FREE | General query |

Prices are defined in `infinitetrading_api/express/src/apiPricing.ts`.

Payment is calculated using `apiPaymentFixed()` in `txFees.ts` which:
1. Gets USD price for the action
2. Fetches live native token price from Redis
3. Converts to wei and deducts from gas wallet

## Redundant Endpoints - Recommended Action

**Status**: Both sets work identically after fixing asset parameter handling.

**Current state**:
- Main: `/lend`, `/borrow`, `/getBorrowed`, `/getSupplied` (port 8003 → 8002 → 8000)
- Sub-router: `/aaveV3/lend`, `/aaveV3/borrow`, `/aaveV3/getBorrowed`, `/aaveV3/getSupplied` (port 8003 → 8002 → 8000)

**Recommendation**: Remove main endpoints, keep `/aaveV3/*` for:
- Clear namespace organization
- Explicit platform indication  
- Future expansion (e.g., `/compoundV3/*`, `/morpho/*`)

**To remove main endpoints**:
1. Remove from `infinitetrading/src/api/gateway/endpoints/lend.R`, `borrow.R`, etc.
2. Remove from `infinitetrading/src/api/helpers/endpoints.R`
3. Run `deployNew.sh` on EC2 to update nginx
4. Restart api-gateway

## Common Issues

### Issue: Both endpoints fail with same error
**Cause**: Problem is in Express API layer, not gateway
**Solution**: Check Express logs, verify gas wallet has ETH

### Issue: Asset conversion returns NULL
**Cause**: Passing contract address to `get_contract()` instead of symbol
**Solution**: Only convert at final Plumber→Express boundary

### Issue: Endpoint returns 404
**Cause**: Nginx config not updated after adding new endpoints
**Solution**: Run `deployNew.sh` to regenerate nginx config

### Issue: Approve fails with "Router address not found"
**Cause**: Plumber API's approve handler doesn't support newer platforms like AAVEv3
**Solution**: USDC must already be approved, or needs manual approval through dHEDGE UI first

---

Last updated: 2026-04-04

