#!/usr/bin/env node

/**
 * Velodrome Auto-Compound Script
 * 
 * Automatically harvests and compounds rewards for all Velodrome LP auto-compounder vaults
 * Runs daily via cron job
 * 
 * Usage: node scripts/velodrome-auto-compound.js
 */

const { ethers } = require("ethers");
const dotenv = require("dotenv");

// Load environment variables from local .env in infinitetrading-sdk folder
dotenv.config();

const ALCHEMY_KEY = process.env.ALCHEMY_API_KEY || process.env.INFURA_PROJECT_ID;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

if (!PRIVATE_KEY) {
  console.error("❌ PRIVATE_KEY not found in environment variables");
  process.exit(1);
}

if (!ALCHEMY_KEY) {
  console.error("❌ ALCHEMY_API_KEY not found in environment variables");
  process.exit(1);
}

// Auto-compounder contract addresses on Optimism
const AUTO_COMPOUNDERS = {
  "ITP/VELO": "0x569D92f0c94C04C74c2f3237983281875D9e2247",
  "ITP/DHT": "0xFCEa66a3333a4A3d911ce86cEf8Bdbb8bC16aCA6",
  "ITP/wstETH": "0x2811a577cf57A2Aa34e94B0Eb56157066717563f",
  "ITP/OP": "0x8A2e22BdA1fF16bdEf27b6072e087452fa874b69",
  "ITP/WBTC": "0x3092F8dE262F363398F15DDE5E609a752938Cc11",
  "ITP/USDC": "0xC4628802a42F83E5bce3caB05A4ac2F6E485F276",
};

// Auto-compounder ABI - only the harvest function
const AUTO_COMPOUNDER_ABI = [
  {
    inputs: [],
    name: "harvest",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "balance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

/**
 * Initialize provider and wallet
 */
function setupConnection() {
  const rpcUrl = `https://opt-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`;
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  return { provider, wallet };
}

/**
 * Check if auto-compounder has balance (TVL > 0)
 */
async function hasBalance(contract, name) {
  try {
    const balance = await contract.balance();
    const hasBalance = balance > BigInt(0);
    console.log(
      `  📊 ${name} balance: ${ethers.formatEther(balance)} LP tokens ${
        hasBalance ? "✅" : "⚠️  (empty)"
      }`
    );
    return hasBalance;
  } catch (error) {
    console.error(`  ❌ Error checking balance for ${name}:`, error.message);
    return false;
  }
}

/**
 * Execute harvest on a single auto-compounder
 */
async function harvestAutoCompounder(wallet, address, name) {
  try {
    console.log(`\n🔄 Processing ${name} (${address})...`);

    const contract = new ethers.Contract(address, AUTO_COMPOUNDER_ABI, wallet);

    // Check if vault has balance before harvesting
    const vaultHasBalance = await hasBalance(contract, name);
    if (!vaultHasBalance) {
      console.log(`  ⏭️  Skipping ${name} - no liquidity`);
      return { success: true, skipped: true, name };
    }

    // Estimate gas
    let gasEstimate;
    try {
      gasEstimate = await contract.harvest.estimateGas();
      console.log(
        `  ⛽ Estimated gas: ${gasEstimate.toString()}`
      );
    } catch (estimateError) {
      console.log(`  ⚠️  Gas estimation failed: ${estimateError.message}`);
      console.log(`  ℹ️  This usually means there are no rewards to harvest yet`);
      return { success: true, skipped: true, name, reason: "no_rewards" };
    }

    // Execute harvest
    console.log(`  📤 Sending harvest transaction...`);
    const tx = await contract.harvest({
      gasLimit: (gasEstimate * BigInt(120)) / BigInt(100), // 20% buffer
    });

    console.log(`  ⏳ Transaction submitted: ${tx.hash}`);
    console.log(`  🔗 https://optimistic.etherscan.io/tx/${tx.hash}`);

    const receipt = await tx.wait();

    if (receipt.status === 1) {
      console.log(`  ✅ ${name} harvested successfully!`);
      console.log(`  📊 Gas used: ${receipt.gasUsed.toString()}`);
      return { success: true, txHash: tx.hash, name, gasUsed: receipt.gasUsed.toString() };
    } else {
      console.log(`  ❌ ${name} transaction failed`);
      return { success: false, error: "Transaction reverted", name };
    }
  } catch (error) {
    console.error(`  ❌ Error harvesting ${name}:`, error.message);
    return { success: false, error: error.message, name };
  }
}

/**
 * Main execution function
 */
async function main() {
  console.log("🌾 Velodrome Auto-Compound Daily Harvest");
  console.log("=" .repeat(60));
  console.log(`📅 Date: ${new Date().toISOString()}`);
  console.log(`🌐 Network: Optimism`);
  console.log(`📋 Auto-compounders to process: ${Object.keys(AUTO_COMPOUNDERS).length}`);
  console.log("=" .repeat(60));

  const { provider, wallet } = setupConnection();

  // Check wallet balance
  const balance = await provider.getBalance(wallet.address);
  console.log(`\n💰 Wallet: ${wallet.address}`);
  console.log(`💵 Balance: ${ethers.formatEther(balance)} ETH`);

  if (balance < ethers.parseEther("0.001")) {
    console.warn("⚠️  Warning: Low ETH balance for gas fees!");
  }

  const results = [];

  // Process each auto-compounder
  for (const [name, address] of Object.entries(AUTO_COMPOUNDERS)) {
    const result = await harvestAutoCompounder(wallet, address, name);
    results.push(result);

    // Wait 2 seconds between transactions to avoid nonce issues
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }

  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("📊 HARVEST SUMMARY");
  console.log("=" .repeat(60));

  const successful = results.filter((r) => r.success && !r.skipped).length;
  const skipped = results.filter((r) => r.skipped).length;
  const failed = results.filter((r) => !r.success).length;

  console.log(`✅ Successful harvests: ${successful}`);
  console.log(`⏭️  Skipped (empty/no rewards): ${skipped}`);
  console.log(`❌ Failed: ${failed}`);

  if (successful > 0) {
    console.log("\n🎉 Harvested pools:");
    results
      .filter((r) => r.success && !r.skipped)
      .forEach((r) => {
        console.log(`  • ${r.name}: ${r.txHash}`);
      });
  }

  if (skipped > 0) {
    console.log("\n⏭️  Skipped pools:");
    results
      .filter((r) => r.skipped)
      .forEach((r) => {
        console.log(`  • ${r.name}${r.reason ? ` (${r.reason})` : ""}`);
      });
  }

  if (failed > 0) {
    console.log("\n❌ Failed pools:");
    results
      .filter((r) => !r.success)
      .forEach((r) => {
        console.log(`  • ${r.name}: ${r.error}`);
      });
  }

  console.log("\n✨ Auto-compound harvest complete!");
  console.log("=" .repeat(60));

  // Exit with error code if any failed
  process.exit(failed > 0 ? 1 : 0);
}

// Run the script
main().catch((error) => {
  console.error("\n💥 Fatal error:", error);
  process.exit(1);
});
