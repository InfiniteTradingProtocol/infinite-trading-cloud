/**
 * Test script for vault guard caching system
 * Run with: npx ts-node test-guard-cache.ts
 */

import { Network } from '@dhedge/v2-sdk';
import { getWhitelistedDexsForVault } from './src/utils/vault-guard-checker';

async function testGuardCache() {
  console.log('🧪 Testing Vault Guard Cache System\n');

  // Test vault on Optimism (known to have guard)
  const vaultAddress = '0x427d9F313fb683F7F84E1F1b22475E99e87dB1BE'; // Example dHEDGE vault
  const network = Network.OPTIMISM;

  console.log(`📍 Testing vault: ${vaultAddress}`);
  console.log(`🌐 Network: ${network}\n`);

  try {
    console.log('🔍 First call (should query guard contract)...');
    const firstCall = await getWhitelistedDexsForVault(vaultAddress, network);
    console.log(`✅ First call result: ${firstCall.length} whitelisted DEXs`);
    console.log(`   DEXs: ${firstCall.join(', ')}\n`);

    console.log('🔍 Second call (should use cache)...');
    const secondCall = await getWhitelistedDexsForVault(vaultAddress, network);
    console.log(`✅ Second call result: ${secondCall.length} whitelisted DEXs`);
    console.log(`   DEXs: ${secondCall.join(', ')}\n`);

    console.log('🎉 Test completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed:', error);
    process.exit(1);
  }
}

testGuardCache();
