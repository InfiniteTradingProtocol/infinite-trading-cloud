/**
 * ODOS API Rate Limiting Patch
 * 
 * This script patches the dHEDGE SDK to add rate limiting and retry logic for ODOS API calls.
 * Run this after npm install to apply the patches.
 * 
 * Usage: node build/src/utils/patchOdosRateLimit.js
 */

const fs = require('fs');
const path = require('path');

const SDK_PATH = path.join(__dirname, '../../node_modules/@dhedge/v2-sdk/dist/v2-sdk.cjs.production.min.js');

console.log('Patching ODOS rate limiting in dHEDGE SDK...');

// Read the SDK file
let sdkContent = fs.readFileSync(SDK_PATH, 'utf8');

// Check if already patched
if (sdkContent.includes('ODOS_RATE_LIMIT_PATCHED')) {
  console.log('SDK already patched with rate limiting.');
  process.exit(0);
}

// Find the axios imports section and add rate limiting code
const rateLimitCode = `
// ODOS_RATE_LIMIT_PATCHED - DO NOT REMOVE THIS COMMENT
const odosRateLimiter = {
  timestamps: new Map(),
  maxRPS: 2,
  async waitForSlot(network) {
    const key = 'odos_' + network;
    const now = Date.now();
    const timestamps = this.timestamps.get(key) || [];
    const valid = timestamps.filter(ts => now - ts < 1000);
    if (valid.length >= this.maxRPS) {
      const wait = 1100 - (now - valid[0]);
      await new Promise(r => setTimeout(r, wait));
      return this.waitForSlot(network);
    }
    valid.push(now);
    this.timestamps.set(key, valid);
  }
};

async function retryOdosCall(fn, maxRetries = 3) {
  let delay = 2000;
  for (let i = 0; i <= maxRetries; i++) {
    try {
      return await fn();
    } catch (err) {
      const is429 = err?.response?.status === 429;
      if (i >= maxRetries || (!is429 && err?.response?.status < 500)) throw err;
      console.warn('ODOS call failed, retry ' + (i+1) + '/' + maxRetries + ' in ' + delay + 'ms');
      await new Promise(r => setTimeout(r, delay));
      delay *= 2;
    }
  }
}
`;

// Insert the rate limiting code at the beginning of the file (after the wrapping function)
const insertPoint = sdkContent.indexOf('var ') === 0 ? sdkContent.indexOf(';') + 1 : 0;
sdkContent = sdkContent.slice(0, insertPoint) + rateLimitCode + sdkContent.slice(insertPoint);

// Find and wrap the ODOS API calls
// Look for axios.post(odosBaseUrl patterns
const odosCallPattern = /axios\.post\(odosBaseUrl\s*\+\s*"([^"]+)"/g;
let match;
const replacements = [];

while ((match = odosCallPattern.exec(sdkContent)) !== null) {
  const fullMatch = match[0];
  const endpoint = match[1];
  replacements.push({
    original: fullMatch,
    replacement: `retryOdosCall(async () => { await odosRateLimiter.waitForSlot(pool.network || 'default'); return axios.post(odosBaseUrl + "${endpoint}"`
  });
}

// Apply replacements
replacements.forEach(({ original, replacement }) => {
  sdkContent = sdkContent.replace(original, replacement);
});

// Need to close the async wrapper - find the closing of axios.post calls
sdkContent = sdkContent.replace(
  /axios\.post\(odosBaseUrl\s*\+\s*"\/quote\/v3",\s*quoteParams,/g,
  'retryOdosCall(async () => { await odosRateLimiter.waitForSlot(pool.network || "default"); return axios.post(odosBaseUrl + "/quote/v3", quoteParams,'
);

sdkContent = sdkContent.replace(
  /axios\.post\(odosBaseUrl\s*\+\s*"\/assemble",\s*assembleParams,/g,
  'retryOdosCall(async () => { await odosRateLimiter.waitForSlot(pool.network || "default"); return axios.post(odosBaseUrl + "/assemble", assembleParams,'
);

// Add closing braces for the retry wrappers
// This is tricky - we need to find where the axios calls end
sdkContent = sdkContent.replace(
  /(\}\);[\s\n]*quoteResult\s*=\s*_context\.sent;)/g,
  '});});\n            quoteResult = _context.sent;'
);

sdkContent = sdkContent.replace(
  /(\}\);[\s\n]*assembleResult\s*=\s*_context\.sent;)/g,
  '});});\n            assembleResult = _context.sent;'
);

// Write the patched file
fs.writeFileSync(SDK_PATH, sdkContent, 'utf8');

console.log('✅ Successfully patched ODOS rate limiting in SDK');
console.log('   - Added rate limiter (2 RPS per network)');
console.log('   - Added retry logic with exponential backoff');
console.log('   - Handles 429 errors gracefully');
