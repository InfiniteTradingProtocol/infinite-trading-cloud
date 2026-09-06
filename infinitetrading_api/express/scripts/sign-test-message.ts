/**
 * scripts/sign-test-message.ts — regenerates a fresh EIP-191 signature over
 * the standard SIGNATURE_MESSAGE used by associateGasWallet/deassociateGasWallet/
 * getAllBots/getAllGasBalance/getAssociatedGasWallets (and any future
 * signature-verified endpoint using the same message).
 *
 * Uses a throwaway, publicly-known test private key (NOT tied to any real
 * funds/wallet) so this is safe to keep in the repo and reuse across parity
 * tests without needing a real user's wallet.
 *
 * Usage:
 *   npx ts-node scripts/sign-test-message.ts
 *   npx ts-node scripts/sign-test-message.ts "<custom message>"
 *
 * Prints: manager address + signature, ready to paste into curl/parity-test.ts.
 */

import { ethers } from 'ethers';

// Well-known Hardhat/Anvil default test account #0 private key — publicly
// documented, holds no real funds, used purely to produce a valid EIP-191
// signature for testing signature-verification logic.
const TEST_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

const DEFAULT_SIGNATURE_MESSAGE =
  'Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations.';

async function main() {
  const message = process.argv[2] || DEFAULT_SIGNATURE_MESSAGE;
  const wallet = new ethers.Wallet(TEST_PRIVATE_KEY);
  const signature = await wallet.signMessage(message);

  console.log('manager (address):', wallet.address);
  console.log('signature:', signature);
  console.log('message used:', JSON.stringify(message));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
