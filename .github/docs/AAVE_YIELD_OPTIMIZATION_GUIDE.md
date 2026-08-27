# AAVE Yield Optimization Strategy - Implementation Guide

## Overview
This implementation adds automatic AAVE v3 lending/unlending to maximize yield during idle periods in trading strategies, while maintaining seamless trade execution.

**⚠️ IMPORTANT: Only WETH and USDC are supported for AAVE lending.**
- Other assets (MORPHO, SNX, wstETH, etc.) will be skipped automatically
- The optimizer checks asset support before attempting to lend
- Unsupported assets will be held in the vault normally

## Files Created

1. **`infinitetrading/src/tradebot/aave_yield_optimizer.R`**
   - Core optimization logic
   - Handles all AAVE interactions (check, lend, unlend, approve)
   - Main function: `execute_trade_with_aave_optimization()`

2. **`infinitetrading/src/strategies/eth_ema_11_33_crossover_with_aave.R`**
   - Example strategy using AAVE optimization
   - Based on existing crossover strategy
   - Can be used as template for other strategies

## Strategy Logic

**⚠️ Supported Assets:** Only **WETH and USDC** can be lent to AAVE v3
- Other assets (MORPHO, SNX, wstETH, WBTC, etc.) are automatically skipped
- No errors thrown - just logs "not supported by AAVE, holding in vault"
- Both target asset AND base asset are checked before lending

### LONG Signal Flow
```
1. Check if USDC is supplied to AAVE
   ├─ If YES → Unlend USDC (free capital)
   └─ If NO → Continue

2. Check if need to buy target asset
   ├─ If YES → Buy asset with USDC
   └─ If NO (already have asset) → Continue

3. Check if asset is supported AND not yet in AAVE
   ├─ If SUPPORTED (WETH/USDC) → Lend to AAVE (start earning)
   └─ If NOT SUPPORTED → Hold in vault (log info message)
```

### SELL/NEUTRAL Signal Flow
```
1. Check if asset is supplied to AAVE
   ├─ If YES → Unlend asset (free for selling)
   └─ If NO → Continue

2. Check if have asset to sell
   ├─ If YES → Sell asset to USDC
   └─ If NO → Continue

3. Lend USDC to AAVE (always supported)
   ├─ USDC is ALWAYS supported by AAVE
   └─ Works even if you sold MORPHO, SNX, or other non-AAVE assets
   └─ Earn yield while waiting for next LONG signal
```

## Safety Features

### Error Handling
- All AAVE operations wrapped in `tryCatch()`
- Failed operations return FALSE but don't crash strategy
- Detailed logging for debugging

### State Verification
- Always checks current AAVE positions before acting
- Refreshes pool composition after each operation
- Validates balances before trading

### Transaction Timing
- 3-5 second delays after transactions for confirmation
- Prevents race conditions
- Ensures blockchain state consistency

## Testing Plan

### Phase 1: Manual Testing (Recommended First)
```r
# Source the optimizer
source("~/infinitetrading/src/tradebot/aave_yield_optimizer.R")

# Test configuration
test_pool <- "0x6a18000ebd71b79d345f9f9753253ae4fff84e27"
test_network <- "optimism"
test_apiKey <- "your_api_key"

# Test 1: Check AAVE positions
usdc_pos <- check_aave_supplied(test_pool, "USDC", test_network, test_apiKey)
weth_pos <- check_aave_supplied(test_pool, "WETH", test_network, test_apiKey)

print(usdc_pos)  # Should show is_supplied and amount
print(weth_pos)

# Test 2: Approve and lend (small amount first!)
# Make sure you have some USDC in the vault first
approve_for_aave(test_pool, "USDC", test_network, test_apiKey)
lend_to_aave(test_pool, "USDC", test_network, share = 10, test_apiKey)  # Only 10% for testing

# Test 3: Check it's lent
Sys.sleep(10)
usdc_pos_after <- check_aave_supplied(test_pool, "USDC", test_network, test_apiKey)
print(usdc_pos_after)  # Should show increased amount

# Test 4: Unlend
unlend_from_aave(test_pool, "USDC", test_network, share = 100, test_apiKey)

# Test 5: Verify unlent
Sys.sleep(10)
usdc_pos_final <- check_aave_supplied(test_pool, "USDC", test_network, test_apiKey)
print(usdc_pos_final)  # Should show 0 or minimal amount
```

### Phase 2: Full Flow Testing
```r
# Test LONG signal execution
execute_trade_with_aave_optimization(
  pool = test_pool,
  pair = "WETH-USDC",
  side = "long",
  network = test_network,
  share = 10,  # Small share for testing
  slippage = 0.5,
  platform = "odos",
  max_usd = 100,  # Small amount for testing
  apiKey = test_apiKey,
  enable_aave = TRUE
)

# Wait and observe logs
# Then test SELL signal
Sys.sleep(60)

execute_trade_with_aave_optimization(
  pool = test_pool,
  pair = "WETH-USDC",
  side = "sell",
  network = test_network,
  share = 100,
  slippage = 0.5,
  platform = "odos",
  max_usd = NULL,
  apiKey = test_apiKey,
  enable_aave = TRUE
)
```

### Phase 3: Strategy Integration Testing
```r
# Run the strategy for one cycle only (modify to exit after 1 loop)
source("~/infinitetrading/src/strategies/eth_ema_11_33_crossover_with_aave.R")

# Monitor logs carefully
# Verify AAVE positions before and after
```

## Deployment Steps

### 1. Deploy Files to EC2
```bash
# From local machine
scp -i ~/.ssh/macmini.pem \
  infinitetrading/src/tradebot/aave_yield_optimizer.R \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading/src/tradebot/

scp -i ~/.ssh/macmini.pem \
  infinitetrading/src/strategies/eth_ema_11_33_crossover_with_aave.R \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com:/home/ubuntu/infinitetrading/src/strategies/
```

### 2. Update PM2 Configuration
```bash
# SSH to EC2
ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com

# Edit ecosystem.config.js to add new strategy
nano ~/infinitetrading_api/ecosystem.config.js
```

Add new entry:
```javascript
{
  name: "strategy-crossover-aave",
  script: "Rscript",
  args: "/home/ubuntu/infinitetrading/src/strategies/eth_ema_11_33_crossover_with_aave.R",
  cwd: "/home/ubuntu/infinitetrading",
  interpreter: "none",
  instances: 1,
  autorestart: true,
  watch: false,
  max_memory_restart: "1G",
  env: {
    ITP_APIKEY: process.env.ITP_APIKEY
  }
}
```

### 3. Start the Strategy
```bash
# Start with PM2
pm2 start ecosystem.config.js --only strategy-crossover-aave

# Monitor logs
pm2 logs strategy-crossover-aave --lines 100
```

### 4. Monitor and Validate

**Check AAVE positions regularly:**
```bash
# Via API
curl -s "https://api.infinitetrading.io/aaveV3/getSupplied?pool=<POOL>&network=optimism&asset=USDC&protocol=dhedge&apiKey=<KEY>" | jq '.'

# Check for WETH too
curl -s "https://api.infinitetrading.io/aaveV3/getSupplied?pool=<POOL>&network=optimism&asset=WETH&protocol=dhedge&apiKey=<KEY>" | jq '.'
```

**Monitor transactions:**
- Check Optimism explorer for vault transactions
- Verify AAVE deposits/withdrawals
- Confirm trades execute correctly

## Troubleshooting

### Issue: "Router address not found for aavev3"
**Solution:** Ensure `dex-approve.ts` has AAVE addresses (already fixed in previous steps)

### Issue: AAVE lend fails with "no balance"
**Solution:** 
- Check pool composition first
- Ensure asset is not already fully lent
- Verify vault has the asset

### Issue: Unlend fails
**Solution:**
- Check if asset is actually supplied: `check_aave_supplied()`
- Verify share parameter is valid (1-100)
- Check vault has enough gas

### Issue: Trade fails after unlend
**Solution:**
- Increase sleep time after unlend (allow more confirmation time)
- Check if unlend actually completed
- Verify pool composition refreshed

## Performance Monitoring

### Key Metrics to Track
1. **Yield earned from AAVE**
   - Compare APY from AAVE vs holding idle
   - Calculate total interest earned

2. **Gas costs**
   - Extra lend/unlend transactions add gas
   - Should be offset by yield earned

3. **Execution timing**
   - Time from signal to trade execution
   - Impact of AAVE operations on latency

4. **Success rate**
   - Percentage of successful AAVE operations
   - Trade execution success with optimization

## Configuration Options

### Per-Strategy AAVE Control
```r
# In strategy file
enable_aave = c(TRUE, TRUE, FALSE)  # Enable for first 2, disable for 3rd
```

### Customizable Parameters
```r
# In aave_yield_optimizer.R
MINIMUM_LEND_AMOUNT <- 10  # Don't lend if less than $10
WAIT_AFTER_LEND <- 5      # Seconds to wait after lending
WAIT_AFTER_UNLEND <- 5    # Seconds to wait after unlending
```

## Rollback Plan

If issues occur, disable AAVE optimization:
```r
# Quick disable in running strategy
enable_aave <- c(FALSE, FALSE, FALSE)

# Or revert to original strategy
pm2 stop strategy-crossover-aave
pm2 start ecosystem.config.js --only strategy-crossovers  # Original
```

## Expected Benefits

1. **Increased yield**: 3-5% APY on idle USDC/WETH in AAVE
2. **Capital efficiency**: Assets always earning, never idle
3. **No strategy changes**: Trading logic remains identical
4. **Automatic optimization**: No manual intervention needed

## Next Steps

1. ✅ Review this guide
2. ⬜ Run manual tests (Phase 1)
3. ⬜ Run full flow tests (Phase 2)
4. ⬜ Deploy to EC2 with monitoring
5. ⬜ Run for 24-48 hours with close monitoring
6. ⬜ Analyze performance and adjust if needed
7. ⬜ Roll out to additional strategies

## Questions to Consider

1. **Which vaults should use this?**
   - Start with one test vault
   - Expand to profitable vaults once proven

2. **Should all strategies use AAVE?**
   - High-frequency strategies: Maybe not (gas costs)
   - Low-frequency strategies: Yes (more idle time)

3. **What about other networks?**
   - AAVE v3 is on Optimism, Polygon, Arbitrum, Base
   - Can enable per network

4. **Risk management?**
   - AAVE has very low risk (blue-chip protocol)
   - Still should monitor smart contract risks
   - Consider insurance protocols

---

**Status:** Ready for testing
**Priority:** Medium-High (good ROI, low risk)
**Complexity:** Medium (well-tested components)
