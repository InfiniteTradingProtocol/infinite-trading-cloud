# LLM Introspection Endpoint (MCP-Style)

## Overview

The `/llmIntrospect` endpoint provides a Model Context Protocol (MCP)-style interface for LLMs to discover and understand the Infinite Trading API capabilities. This endpoint returns structured, comprehensive documentation about all publicly available endpoints, making it easy for AI agents to interact with the API programmatically.

## Endpoint Details

- **Path**: `/llmIntrospect`
- **Method**: `GET`
- **Authentication**: Not required (public documentation endpoint)
- **Rate Limit**: Standard API rate limits apply (600 requests/minute per IP)

## Usage

### Basic Request

```bash
curl -X GET "https://api.infinitetrading.io/llmIntrospect"
```

### Response Structure

The endpoint returns a comprehensive JSON object with the following sections:

#### 1. API Information
General information about the API including title, version, description, base URL, and authentication requirements.

```json
{
  "api_info": {
    "title": "Infinite Trading Protocol API",
    "version": "1.0.0",
    "description": "Deploy automated trading strategies in DeFi...",
    "base_url": "https://api.infinitetrading.io",
    "documentation": "https://www.infinitetrading.io/docs",
    "authentication": "All endpoints require an API key..."
  }
}
```

#### 2. Categories
Organized categories of API functionality:

- **Asset Management**: Approve and manage assets
- **Trading**: Execute trades within vault pools
- **Automation**: Configure automated trading bots
- **Market Data**: Historical and real-time data
- **Portfolio**: Portfolio composition queries
- **Wallet**: Gas wallet management
- **Blockchain**: Contract and token interactions
- **DeFi Lending**: Aave V3 protocol operations
- **Authentication**: API key management
- **Pool Management**: Pool fees and configurations
- **CEX Integration**: Centralized exchange integration

#### 3. Endpoints
Detailed information for each endpoint including:

- `name`: Endpoint identifier
- `method`: HTTP method (GET/POST)
- `path`: URL path
- `category`: Functional category
- `description`: Detailed explanation of purpose
- `parameters`: Array of parameter objects with:
  - `name`: Parameter name
  - `type`: Data type (string, number, boolean)
  - `required`: Whether parameter is mandatory
  - `description`: Parameter purpose
  - `default`: Default value (if applicable)

Example endpoint entry:
```json
{
  "name": "vaultTrade",
  "method": "POST",
  "path": "/vaultTrade",
  "category": "Trading",
  "description": "Execute trades inside a specific pool...",
  "parameters": [
    {
      "name": "apiKey",
      "type": "string",
      "required": true,
      "description": "API key for authentication"
    },
    ...
  ]
}
```

#### 4. Networks
List of supported blockchain networks:
- Optimism
- Base
- Arbitrum
- Polygon

#### 5. Protocols
Supported DeFi protocols:
- dHEDGE
- Aave V3
- Uniswap
- Velodrome

#### 6. Platforms
Available platforms for trade execution:
- **odos**: DEX Aggregator for optimal swap routing
- **aave**: Lending Protocol for lending and borrowing

#### 7. Usage Notes
Important guidelines for API usage:
- Asset approval requirements
- API key generation
- Rate limiting
- Short position requirements
- Parameter behavior

#### 8. Error Codes
Common HTTP status codes and API-specific error codes

## Features

### 1. **Non-Hidden Endpoints Only**
The endpoint filters out internal/hidden endpoints, exposing only public-facing functionality that LLMs should access.

### 2. **Comprehensive Parameter Documentation**
Each endpoint includes complete parameter specifications with types, requirements, defaults, and descriptions.

### 3. **Categorized Organization**
Endpoints are organized by functional category, making it easy for LLMs to discover related functionality.

### 4. **Usage Guidelines**
Includes best practices, common patterns, and important notes for successful API interaction.

### 5. **Error Code Reference**
Complete error code documentation helps LLMs handle failures gracefully.

## Use Cases for LLMs

### 1. **API Discovery**
LLMs can query this endpoint to understand what operations are available without needing external documentation.

### 2. **Dynamic Function Calling**
The structured parameter information enables LLMs to construct valid API calls programmatically.

### 3. **Context-Aware Assistance**
LLMs can provide accurate guidance about API capabilities and requirements to users.

### 4. **Automated Integration**
AI agents can use this endpoint to automatically integrate with the Infinite Trading API.

### 5. **Error Handling**
The error code documentation helps LLMs diagnose and recover from API errors.

## Example LLM Workflow

1. **Discovery**: LLM queries `/llmIntrospect` to understand available capabilities
2. **Analysis**: LLM parses the response to identify relevant endpoints for user request
3. **Validation**: LLM checks parameter requirements and formats
4. **Execution**: LLM constructs and executes appropriate API calls
5. **Error Handling**: LLM interprets responses using error code documentation

## Integration Example

```javascript
// Fetch API documentation
const apiDocs = await fetch('https://api.infinitetrading.io/llmIntrospect')
  .then(res => res.json());

// Find trading endpoints
const tradingEndpoints = apiDocs.endpoints.filter(
  ep => ep.category === 'Trading'
);

// Get vaultTrade endpoint details
const vaultTradeEndpoint = tradingEndpoints.find(
  ep => ep.name === 'vaultTrade'
);

// Construct API call based on parameters
const requiredParams = vaultTradeEndpoint.parameters.filter(
  p => p.required
);

console.log('Required parameters:', requiredParams.map(p => p.name));
```

## Hidden Endpoints

The following endpoints are intentionally excluded from the introspection response as they are for internal use or require special permissions:

- `/createGasWallet`
- `/linkGasWallet`
- `/unlinkGasWallet`
- `/getAllBots`
- `/getAllGasBalance`
- `/getEstimatedAnualYield`
- `/getTotalYield`
- `/getAllYields`
- `/getGasWalletPools`
- `/associateGasWallet`
- `/deassociateGasWallet`
- `/getAssociatedGasWallets`
- `/getAllCEXSubaccounts`
- `/setCEXStrategy`

## Security Considerations

1. **No Authentication Required**: This endpoint is publicly accessible as it only returns documentation
2. **No Sensitive Data**: Response contains only API structure information, no user data
3. **Rate Limited**: Standard rate limits prevent abuse
4. **Read-Only**: GET method with no side effects

## Maintenance

When adding new endpoints to the API:

1. Update the `llmIntrospect.R` file with the new endpoint documentation
2. Ensure the endpoint is not in the `hidden_endpoints` list if it should be public
3. Include comprehensive parameter documentation
4. Add appropriate category assignment
5. Test the introspection response after deployment

## Response Size

The typical response size is approximately 10-15KB, making it efficient for LLM context windows while remaining comprehensive.

## Version History

- **v1.0.0** (2026-04-16): Initial release with MCP-style introspection
  - 20 documented public endpoints
  - 11 functional categories
  - Comprehensive parameter documentation
  - Usage guidelines and error codes
