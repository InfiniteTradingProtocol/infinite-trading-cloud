# LLM Integration Example

This document demonstrates how an LLM or AI agent would use the `/llmIntrospect` endpoint to discover and interact with the Infinite Trading API.

## Scenario: AI Trading Assistant

An AI assistant needs to help a user execute a trade on their DeFi vault. Here's how it would use the introspection endpoint:

### Step 1: Discover API Capabilities

```javascript
// AI Agent queries the introspection endpoint
const apiDocs = await fetch('https://api.infinitetrading.io/llmIntrospect')
  .then(res => res.json());

console.log('API Title:', apiDocs.api_info.title);
console.log('Total Endpoints:', apiDocs.endpoints.length);
```

### Step 2: Find Relevant Endpoint

```javascript
// User request: "I want to swap USDC to ETH in my vault"
// AI searches for trading-related endpoints

const tradingEndpoints = apiDocs.endpoints.filter(
  endpoint => endpoint.category === 'Trading'
);

console.log('Trading Endpoints:', tradingEndpoints.map(e => e.name));
// Output: ['vaultTrade']

const vaultTradeEndpoint = tradingEndpoints[0];
```

### Step 3: Understand Required Parameters

```javascript
// Extract required parameters
const requiredParams = vaultTradeEndpoint.parameters.filter(p => p.required);
const optionalParams = vaultTradeEndpoint.parameters.filter(p => !p.required);

console.log('Required:', requiredParams.map(p => p.name));
// Output: ['apiKey', 'protocol', 'pool', 'network', 'from', 'to']

console.log('Optional:', optionalParams.map(p => `${p.name} (default: ${p.default})`));
// Output: ['amount (default: NA)', 'slippage (default: 0.5)', 'share (default: 100)', 'platform (default: odos)']
```

### Step 4: Validate Networks and Protocols

```javascript
// Check supported networks
console.log('Supported Networks:', apiDocs.networks);
// Output: ['Optimism', 'Base', 'Arbitrum', 'Polygon']

// Check supported protocols
console.log('Supported Protocols:', apiDocs.protocols);
// Output: ['dHEDGE', 'Aave V3', 'Uniswap', 'Velodrome']

// Check supported platforms
const platforms = apiDocs.platforms.map(p => `${p.name}: ${p.use_case}`);
console.log('Platforms:', platforms);
// Output: ['odos: Optimal swap routing', 'aave: Lending and borrowing']
```

### Step 5: Construct API Call

```javascript
// AI constructs the API call based on user input and documentation
const tradeRequest = {
  apiKey: 'user_provided_api_key',
  protocol: 'dhedge',       // from supported protocols
  pool: '0xabc...def',      // user's vault address
  network: 'optimism',      // from supported networks
  from: 'USDC',             // user wants to sell USDC
  to: 'ETH',                // user wants to buy ETH
  share: 50,                // use 50% of USDC balance
  slippage: 1,              // 1% slippage tolerance
  platform: 'odos'          // use odos for optimal routing
};

// Execute the trade
const response = await fetch('https://api.infinitetrading.io/vaultTrade', {
  method: vaultTradeEndpoint.method,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(tradeRequest)
});

const result = await response.json();
console.log('Trade Result:', result);
```

### Step 6: Handle Errors

```javascript
// AI checks error codes from documentation
if (result.status === 'fail') {
  const errorInfo = apiDocs.error_codes.find(
    e => e.code === result.status_code
  );
  
  console.log(`Error ${result.status_code}: ${errorInfo.description}`);
  console.log('Message:', result.message);
  
  // AI can provide helpful guidance based on error
  if (result.status_code === 1007) {
    console.log('💡 Suggestion: Share must be between 1-100');
  }
}
```

## Scenario: Asset Approval Before Trading

The AI learns from the usage notes that assets must be approved before trading:

```javascript
// From apiDocs.usage_notes
const usageNotes = apiDocs.usage_notes;
console.log(usageNotes[0]); 
// "Always approve assets before trading or lending operations"

// AI discovers the approve endpoint
const approveEndpoint = apiDocs.endpoints.find(e => e.name === 'approve');
console.log('Approve Endpoint:', approveEndpoint);

// AI constructs approval request first
const approveRequest = {
  apiKey: 'user_provided_api_key',
  network: 'optimism',
  protocol: 'dhedge',
  pool: '0xabc...def',
  asset: 'USDC',
  platform: 'odos'
};

// Execute approval
await fetch('https://api.infinitetrading.io/approve', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(approveRequest)
});

// Then proceed with trade...
```

## Scenario: Setting Up Automated Trading Bot

User wants to create a bot that automatically goes long on BTC:

```javascript
// AI finds automation endpoints
const automationEndpoints = apiDocs.endpoints.filter(
  e => e.category === 'Automation'
);

console.log('Automation Endpoints:', automationEndpoints.map(e => e.name));
// Output: ['setBot', 'deleteBot']

const setBotEndpoint = automationEndpoints.find(e => e.name === 'setBot');

// AI understands the side options from description
console.log('Description:', setBotEndpoint.description);
// "Configure an automated trading bot with strategy sides (long, short, hold, neutral)..."

// Construct bot configuration
const botConfig = {
  apiKey: 'user_provided_api_key',
  protocol: 'dhedge',
  pool: '0xabc...def',
  network: 'optimism',
  pair: 'BTC-USD',
  side: 'long',              // AI learned valid options: long, short, hold, neutral
  threshold: 1,
  max_usd: 5000,
  slippage: 1,
  share: 100,
  platform: 'odos',
  lending: true              // Enable lending integration
};

await fetch('https://api.infinitetrading.io/setBot', {
  method: 'POST',
  body: JSON.stringify(botConfig)
});
```

## Scenario: Checking Aave V3 Operations

User wants to lend USDC on Aave:

```javascript
// AI finds DeFi Lending endpoints
const lendingEndpoints = apiDocs.endpoints.filter(
  e => e.category === 'DeFi Lending'
);

const aaveEndpoint = lendingEndpoints[0];
console.log('Subroutes:', aaveEndpoint.subroutes);
// Output: [
//   "/lend - Supply assets to Aave for lending",
//   "/unlend - Withdraw supplied assets from Aave",
//   ...
// ]

// AI constructs lending request
const lendRequest = {
  apiKey: 'user_provided_api_key',
  protocol: 'dhedge',
  network: 'optimism',
  pool: '0xabc...def',
  asset: 'USDC',
  share: 30  // Lend 30% of USDC
};

// Use the /lend subroute
await fetch('https://api.infinitetrading.io/aaveV3/lend', {
  method: 'POST',
  body: JSON.stringify(lendRequest)
});
```

## Python Example: Building an LLM Function

```python
import requests
import json

class InfiniteTradingAPI:
    """AI-powered trading API client using introspection."""
    
    def __init__(self, base_url="https://api.infinitetrading.io"):
        self.base_url = base_url
        self.docs = self._load_docs()
    
    def _load_docs(self):
        """Load API documentation via introspection."""
        response = requests.get(f"{self.base_url}/llmIntrospect")
        return response.json()
    
    def list_capabilities(self):
        """List all available API capabilities."""
        categories = {}
        for endpoint in self.docs['endpoints']:
            category = endpoint['category']
            if category not in categories:
                categories[category] = []
            categories[category].append(endpoint['name'])
        return categories
    
    def get_endpoint_info(self, endpoint_name):
        """Get detailed information about a specific endpoint."""
        for endpoint in self.docs['endpoints']:
            if endpoint['name'] == endpoint_name:
                return endpoint
        return None
    
    def validate_parameters(self, endpoint_name, params):
        """Validate parameters before making API call."""
        endpoint = self.get_endpoint_info(endpoint_name)
        if not endpoint:
            return False, f"Endpoint {endpoint_name} not found"
        
        required_params = [
            p['name'] for p in endpoint['parameters'] if p['required']
        ]
        
        missing = [p for p in required_params if p not in params]
        if missing:
            return False, f"Missing required parameters: {missing}"
        
        return True, "Valid"
    
    def execute_trade(self, api_key, pool, network, from_asset, to_asset, 
                      protocol="dhedge", share=100, slippage=0.5):
        """Execute a vault trade with validation."""
        params = {
            'apiKey': api_key,
            'protocol': protocol,
            'pool': pool,
            'network': network,
            'from': from_asset,
            'to': to_asset,
            'share': share,
            'slippage': slippage
        }
        
        # Validate parameters
        valid, msg = self.validate_parameters('vaultTrade', params)
        if not valid:
            return {'status': 'error', 'message': msg}
        
        # Execute
        response = requests.post(
            f"{self.base_url}/vaultTrade",
            json=params
        )
        return response.json()

# Usage
api = InfiniteTradingAPI()

# Discover capabilities
print("API Capabilities:")
capabilities = api.list_capabilities()
for category, endpoints in capabilities.items():
    print(f"  {category}: {', '.join(endpoints)}")

# Execute a trade
result = api.execute_trade(
    api_key="your_api_key",
    pool="0xabc...def",
    network="optimism",
    from_asset="USDC",
    to_asset="ETH",
    share=50
)
print("Trade Result:", result)
```

## Benefits for LLMs

1. **Self-Discovery**: LLMs can discover API capabilities without hardcoded knowledge
2. **Parameter Validation**: Structured parameter info prevents invalid API calls
3. **Error Handling**: Error code documentation enables better error recovery
4. **Up-to-Date**: Always reflects current API state without LLM retraining
5. **Context Efficiency**: Single endpoint provides all necessary information
6. **Type Safety**: Parameter types and requirements are explicit

## Rate Limiting Awareness

From the documentation, LLMs learn:
- 600 requests per minute per IP
- Can implement backoff strategies
- Should batch operations when possible

```javascript
// AI implements rate limiting awareness
const rateLimitInfo = apiDocs.api_info.authentication;
console.log(rateLimitInfo);

// AI tracks requests and implements delays if needed
let requestCount = 0;
const MAX_REQUESTS = 600;
const TIME_WINDOW = 60000; // 1 minute

async function rateLimitedRequest(url, options) {
  if (requestCount >= MAX_REQUESTS) {
    await new Promise(resolve => setTimeout(resolve, TIME_WINDOW));
    requestCount = 0;
  }
  requestCount++;
  return fetch(url, options);
}
```

This introspection-based approach enables LLMs to be self-sufficient, adaptive, and accurate when interacting with the Infinite Trading API.
