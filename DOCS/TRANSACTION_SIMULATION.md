# Transaction Simulation Guide

## Overview

Transaction simulation allows you to test transactions **before** executing them on-chain. This helps you:
- ✅ Avoid wasting gas on failed transactions
- ✅ Detect reverts before they happen
- ✅ Get clear error messages about what will fail
- ✅ Save money by preventing failed transaction costs

## How It Works

### 1. **Gas Estimation (Already Implemented)**

Your trading system **already uses simulation** through gas estimation:

```typescript
// This internally calls eth_call to simulate the transaction
const estimatedGas = await pool.trade(dApp, assetA, assetB, amount, slippage, txOptions, true);
//                                                                                        ^^^^ 
//                                                                                 estimateGasOnly = true
```

When `estimateGasOnly: true`, the SDK:
1. Calls `eth_estimateGas` which uses `eth_call` internally
2. Simulates the transaction without broadcasting it
3. Returns an error if the transaction would revert
4. Provides gas estimate if successful

**Location:** `/requests/trade.ts` lines ~420-550

### 2. **New Explicit Simulation (Just Added)**

For even more control, we've added explicit simulation utilities:

**File:** `/utils/tx-simulator.ts`

#### Key Functions:

##### `simulateTransaction()`
Simulates any raw transaction before sending:
```typescript
const simulation = await simulateTransaction(tx, wallet, network, provider);

if (!simulation.success) {
  console.error(`Transaction would revert: ${simulation.error}`);
  // Don't send the transaction - save gas!
  return;
}

// Safe to send
const sentTx = await wallet.sendTransaction(tx);
```

##### `simulatePoolTrade()`
Simulates a dHEDGE pool trade:
```typescript
const simulation = await simulatePoolTrade(
  pool, 
  dapp, 
  tokenFrom, 
  tokenTo, 
  amount, 
  slippage, 
  txOptions
);

if (!simulation.success) {
  console.error(`Trade would fail: ${simulation.error}`);
  // Try different DEX or adjust parameters
}
```

##### `simulateContractCall()`
Simulates specific contract method calls:
```typescript
const simulation = await simulateContractCall(
  tokenContract,
  'transfer',
  [recipient, amount]
);
```

## Current Implementation Status

### ✅ **Already Simulating:**

1. **All Trades** - Gas estimation catches reverts before execution
   - File: `/requests/trade.ts`
   - Method: `pool.trade(..., true)` for estimation

2. **Payment Transactions** - Now simulated before sending
   - File: `/txFees.ts` 
   - Uses: `simulateTransaction()` before `wallet.sendTransaction()`

3. **Allowance Checks** - Proactive checking before trades
   - File: `/utils/dex-approve.ts`
   - Checks allowance, only approves if needed

### 🔧 **Error Detection:**

Your code already detects these errors during simulation:

```typescript
// From trade.ts line ~455
if (estimatedGas && typeof estimatedGas === 'object' && 
    (estimatedGas as any).gasEstimationError) {
    
    const gasError = (estimatedGas as any).gasEstimationError;
    const errorMsg = gasError?.message || String(gasError);
    
    // Now we know the transaction would fail BEFORE spending gas
    console.error("Gas estimation failed:", errorMsg);
    
    // Check specific error types
    if (errorMsg.includes('allowance')) {
        // Auto-approve and retry
    } else if (errorMsg.includes('balance')) {
        // Insufficient balance error
    } else if (errorMsg.includes('slippage')) {
        // Price moved, need higher slippage
    }
}
```

## How Simulation Prevents Gas Waste

### Without Simulation:
```
1. Build transaction
2. Sign transaction  
3. Send to blockchain ❌ REVERTS
4. Pay gas fees for failed transaction 💸
```

### With Simulation (Your Current Setup):
```
1. Build transaction
2. Simulate with eth_call ✅ (no cost)
3. Detect revert reason
4. Fix issue (approve, adjust slippage, etc.)
5. Simulate again ✅ Success!
6. Send to blockchain ✅
7. Pay gas only for successful transaction 💰
```

## Common Revert Reasons Detected

Your simulation catches these issues **before** spending gas:

| Error Type | Detection | Auto-Fix |
|------------|-----------|----------|
| Insufficient Allowance | ✅ Gas estimation | ✅ Auto-approve |
| Insufficient Balance | ✅ Gas estimation | ⚠️ Need more funds |
| Slippage Too Low | ✅ Gas estimation | ⚠️ Increase slippage |
| Expired Quote | ✅ Gas estimation | ⚠️ Get new quote |
| No Liquidity | ✅ Gas estimation | ⚠️ Try different DEX |
| Invalid Recipient | ✅ Gas estimation | ⚠️ Fix address |

## Usage Examples

### Example 1: Safe Payment Transaction

```typescript
// Build payment transaction
const tx = {
  to: recipientAddress,
  value: ethers.utils.parseEther("1.0"),
  gasLimit: 21000,
  maxFeePerGas: feeData.maxFeePerGas,
  maxPriorityFeePerGas: feeData.maxPriorityFeePerGas
};

// Simulate first (NO GAS COST)
const simulation = await simulateTransaction(tx, wallet, network);

if (!simulation.success) {
  console.error(`Would fail: ${simulation.error}`);
  // Don't send - we just saved gas!
  return { error: simulation.error };
}

// Safe to send
const sentTx = await wallet.sendTransaction(tx);
```

### Example 2: Trade with Pre-Simulation

```typescript
// Estimate gas (internally simulates)
const estimatedGas = await pool.trade(
  dapp, 
  tokenA, 
  tokenB, 
  amount, 
  slippage, 
  txOptions, 
  true  // estimateGasOnly - simulates without sending
);

// Check if simulation detected errors
if (estimatedGas?.gasEstimationError) {
  const error = estimatedGas.gasEstimationError;
  console.error("Trade would fail:", error.message);
  
  // Try to fix the issue
  if (error.message.includes('allowance')) {
    await approveToken();
    // Retry simulation
  }
  
  return { error: "Trade simulation failed" };
}

// Simulation passed - safe to execute
const tx = await pool.trade(
  dapp, 
  tokenA, 
  tokenB, 
  amount, 
  slippage, 
  txOptions, 
  false  // Execute for real
);
```

## Best Practices

### ✅ Do:
1. **Always simulate before expensive operations**
2. **Parse error messages to determine root cause**
3. **Auto-fix when possible (e.g., approvals)**
4. **Log simulation results for debugging**
5. **Use higher slippage for volatile assets**

### ❌ Don't:
1. **Don't skip simulation for "simple" transactions** - they can still fail
2. **Don't ignore simulation errors** - they're preventing gas waste
3. **Don't retry without fixing the issue** - same error will occur
4. **Don't simulate too close to execution** - on-chain state can change

## Technical Details

### How `eth_call` Works

```typescript
// eth_call simulates transaction execution
// Returns: success data OR revert reason
// Cost: FREE (doesn't modify blockchain)

const result = await provider.call({
  from: walletAddress,
  to: contractAddress,
  data: encodedFunctionCall,
  value: ethValue
});

// If it reverts, you get the error message
// If it succeeds, you get the return data
```

### Gas Estimation Internal Process

```typescript
// eth_estimateGas uses eth_call internally
// Then calculates minimum gas needed

const gasEstimate = await provider.estimateGas(transaction);

// Process:
// 1. Simulate with eth_call (binary search for gas)
// 2. Return minimum gas needed
// 3. If simulation reverts, throw error with reason
```

## Integration with Your Workflow

Your trading bots already benefit from simulation:

```
Bot Signal
    ↓
Build Trade
    ↓
Estimate Gas ← SIMULATION (catches errors)
    ↓
[If error] → Fix issue → Retry
    ↓
Execute Trade
    ↓
Confirm Success
```

## Monitoring & Debugging

Check simulation results in logs:

```bash
# See simulation results
pm2 logs infinitetrading-api --lines 100 | grep -i "simulat\|gas estimation"

# See caught errors (gas saved!)
pm2 logs infinitetrading-api | grep -i "gas estimation failed\|simulation failed"

# See successful trades
pm2 logs infinitetrading-api | grep "trade tx hash"
```

## Cost Savings

Simulation has **zero cost** because:
- `eth_call` is read-only (no state changes)
- `eth_estimateGas` is read-only 
- Only successful transactions pay gas
- Failed simulations are free

**Example savings per day:**
- Without simulation: 10 failed trades × 0.001 ETH = 0.01 ETH lost
- With simulation: 10 caught errors × 0 ETH = 0 ETH saved ✅

## Additional Resources

- **Ethers.js Simulation**: https://docs.ethers.org/v5/api/providers/provider/#Provider-call
- **Gas Estimation**: https://docs.ethers.org/v5/api/providers/provider/#Provider-estimateGas
- **EIP-1559**: https://eips.ethereum.org/EIPS/eip-1559

---

**Summary:** Your system already uses transaction simulation through gas estimation, catching errors before they cost you gas. The new utilities in `tx-simulator.ts` provide even more control for custom transactions.
