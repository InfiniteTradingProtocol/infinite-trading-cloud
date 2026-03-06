// Test multicall batch endpoint locally
const axios = require('axios');

const testPools = [
  "0xb48a390270d41a1663a68708210b7ef4d89ba9f6", // Polygon pool 1
  "0x4bc2ee59d978a107addc3ab934722c4f01425b9e"  // Polygon pool 2
];

async function testBatchEndpoint() {
  try {
    console.log('🧪 Testing multicall batch endpoint...');
    console.log(`📊 Testing with ${testPools.length} pools`);
    
    const response = await axios.post(
      'http://localhost:8000/poolCompositionBatch?network=polygon',
      { pools: testPools },
      { 
        headers: { 'Content-Type': 'application/json' },
        timeout: 30000 
      }
    );
    
    console.log('\n✅ SUCCESS!');
    console.log('Status:', response.data.status);
    console.log('Count:', response.data.count);
    console.log('\nResults:');
    
    response.data.results.forEach((result, i) => {
      console.log(`\nPool ${i + 1}: ${result.pool}`);
      console.log(`  Success: ${result.success}`);
      if (result.success) {
        console.log(`  Composition items: ${result.composition.length}`);
        result.composition.slice(0, 2).forEach((item, j) => {
          console.log(`    Asset ${j + 1}: ${item.asset}`);
          console.log(`      Balance: ${item.balance.hex || item.balance}`);
          console.log(`      Rate: ${item.rate.hex || item.rate}`);
        });
      } else {
        console.log(`  Error: ${result.error}`);
      }
    });
    
  } catch (error) {
    console.error('\n❌ FAILED!');
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Data:', JSON.stringify(error.response.data, null, 2));
    } else {
      console.error('Error:', error.message);
    }
    process.exit(1);
  }
}

testBatchEndpoint();
