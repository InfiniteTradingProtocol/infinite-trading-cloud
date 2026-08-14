# Velodrome Auto-Compound Script

This script automatically harvests and compounds rewards for all Velodrome LP auto-compounder vaults on Optimism.

## Auto-Compounder Contracts

The script manages the following Velodrome LP auto-compounders:

| Pool | Contract Address |
|------|------------------|
| ITP/VELO | `0x569D92f0c94C04C74c2f3237983281875D9e2247` |
| ITP/DHT | `0xFCEa66a3333a4A3d911ce86cEf8Bdbb8bC16aCA6` |
| ITP/wstETH | `0x2811a577cf57A2Aa34e94B0Eb56157066717563f` |
| ITP/OP | `0x8A2e22BdA1fF16bdEf27b6072e087452fa874b69` |
| ITP/WBTC | `0x3092F8dE262F363398F15DDE5E609a752938Cc11` |
| ITP/USDC | `0xC4628802a42F83E5bce3caB05A4ac2F6E485F276` |

## How It Works

1. **Daily Harvest**: The script runs once per day at a scheduled UTC time
2. **Check Balance**: Before harvesting, it checks if each vault has liquidity (TVL > 0)
3. **Gas Estimation**: Estimates gas for the harvest transaction to verify there are rewards
4. **Harvest**: Calls the `harvest()` function on each auto-compounder contract
5. **Compound**: The contract automatically:
   - Claims VELO rewards from Velodrome gauges
   - Swaps rewards back into LP tokens
   - Restakes the LP tokens to compound yields

## Setup

### 1. Install Dependencies

```bash
cd /home/ubuntu/infinite-trading-cloud
npm install ethers dotenv
```

### 2. Configure Environment Variables

Ensure your `.env` file contains:

```bash
PRIVATE_KEY=your_private_key_here
INFURA_PROJECT_ID=your_infura_project_id
```

**Note:** This uses the same wallet as the cbEGGS liquidate script.

### 3. Deploy with Cron (Production)

Production runs this job from the ubuntu user crontab on EC2.

```bash
# Edit user crontab
crontab -e

# Daily schedule (UTC) - current production setting
37 13 * * * cd /home/ubuntu/infinitetrading-sdk && /usr/bin/node velodrome-auto-compound.js >> /home/ubuntu/infinitetrading_api/logs/velodrome-auto-compound-cron.log 2>&1

# Verify current schedule
crontab -l
```

### 4. Manual Execution

To run the script manually:

```bash
cd /home/ubuntu/infinite-trading-cloud
node scripts/velodrome-auto-compound.js
```

## Schedule

- **Frequency**: Once per day
- **Time**: 13:37 UTC
- **Cron Expression**: `37 13 * * *`

## Monitoring

### Cron Commands

```bash
# Check schedule
crontab -l

# View latest harvest logs
tail -n 100 /home/ubuntu/infinitetrading_api/logs/velodrome-auto-compound-cron.log

# Run manually once
cd /home/ubuntu/infinitetrading-sdk && /usr/bin/node velodrome-auto-compound.js
```

### Log Files

Logs are stored in `/home/ubuntu/infinitetrading_api/logs/`:

- `velodrome-auto-compound-out.log` - Standard output
- `velodrome-auto-compound-error.log` - Errors only

Logs are automatically:
- Rotated when they reach 20MB
- Retained for 30 days
- Compressed with gzip

## Output Example

```
🌾 Velodrome Auto-Compound Daily Harvest
============================================================
📅 Date: 2026-04-02T12:00:00.000Z
🌐 Network: Optimism
📋 Auto-compounders to process: 6
============================================================

💰 Wallet: 0x...
💵 Balance: 0.05 ETH

🔄 Processing ITP/VELO (0x569D92f0c94C04C74c2f3237983281875D9e2247)...
  📊 ITP/VELO balance: 1234.56 LP tokens ✅
  ⛽ Estimated gas: 250000
  📤 Sending harvest transaction...
  ⏳ Transaction submitted: 0xabc...
  🔗 https://optimistic.etherscan.io/tx/0xabc...
  ✅ ITP/VELO harvested successfully!
  📊 Gas used: 230000

============================================================
📊 HARVEST SUMMARY
============================================================
✅ Successful harvests: 4
⏭️  Skipped (empty/no rewards): 2
❌ Failed: 0

🎉 Harvested pools:
  • ITP/VELO: 0xabc...
  • ITP/DHT: 0xdef...
  • ITP/wstETH: 0xghi...
  • ITP/OP: 0xjkl...

⏭️  Skipped pools:
  • ITP/WBTC (no_rewards)
  • ITP/USDC (no_rewards)

✨ Auto-compound harvest complete!
============================================================
```

## Troubleshooting

### Low Gas Balance

If you see `⚠️  Warning: Low ETH balance for gas fees!`, add more ETH to the wallet:

```bash
# Check wallet address
grep PRIVATE_KEY /home/ubuntu/infinitetrading_api/.env
```

### Gas Estimation Fails

This usually means there are no rewards to harvest yet. The script will skip and try again the next day.

### Transaction Reverts

Check the transaction on Optimistic Etherscan to see the revert reason. Common causes:
- Insufficient gas
- Contract paused
- No rewards available

### Script Not Running

```bash
# Check cron schedule
crontab -l

# Check cron execution log
tail -n 200 /home/ubuntu/infinitetrading_api/logs/velodrome-auto-compound-cron.log
```

## Gas Costs

Estimated gas per harvest transaction:
- **Gas Limit**: ~250,000 gas
- **Gas Price**: ~0.001 gwei on Optimism
- **Cost per harvest**: ~$0.0001 USD
- **Daily cost**: ~$0.0006 USD (6 vaults)
- **Monthly cost**: ~$0.018 USD

## Security

- Uses the same wallet as cbEGGS liquidate script
- Private key stored in environment variables
- No admin privileges required
- Only calls public `harvest()` function

## Smart Contract Details

Each auto-compounder contract implements:

```solidity
function harvest() external {
    // 1. Claim VELO rewards from gauge
    // 2. Swap VELO for LP tokens via DEX
    // 3. Add liquidity back to the pool
    // 4. Restake LP tokens in gauge
    // 5. Pay 1% rewards to harvester in ITP tokens
}
```

## Support

For issues or questions:
- Check logs: `pm2 logs velodrome-auto-compound`
- View on Etherscan: https://optimistic.etherscan.io/
- Review auto-compounder contracts in infinite-trading-frontend repo
