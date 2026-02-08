import { ethers } from "ethers";

export async function waitForSuccess(tx: ethers.providers.TransactionResponse, provider: ethers.providers.Provider, timeoutMs = 30_000, confirmations = 1) {
  const timer = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("Transaction receipt timeout")), timeoutMs)
  );
  // prefer waiting on the tx object; fall back to provider if needed
  const receipt = await Promise.race([
    tx.wait(confirmations),
    timer,
  ]);
  if (!receipt || receipt.status !== 1) {
    throw new Error(`Transaction failed or reverted (hash: ${tx.hash})`);
  }
  return receipt; // includes effectiveGasPrice, gasUsed, etc.
}
