# LLM Introspection Endpoint - Architecture

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         LLM / AI Agent                              │
│                                                                     │
│  1. Discovers API capabilities                                     │
│  2. Validates parameters                                           │
│  3. Constructs API calls                                           │
│  4. Handles errors intelligently                                   │
└──────────────────────┬──────────────────────────────────────────────┘
                       │
                       │ GET /llmIntrospect
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    API Gateway (gateway.R)                          │
│                    Host: 0.0.0.0:8003                              │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │              Rate Limit Middleware                        │    │
│  │              (600 req/min per IP)                         │    │
│  └───────────────────────────────────────────────────────────┘    │
│                       │                                            │
│  ┌────────────────────▼───────────────────────────────────────┐   │
│  │           Endpoint Router (Plumber)                        │   │
│  │                                                            │   │
│  │  • Load endpoints from endpoints array                    │   │
│  │  • Mount each endpoint handler                            │   │
│  │  • Apply middleware                                       │   │
│  │  • Filter hidden endpoints from docs                     │   │
│  └────────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│              /llmIntrospect Endpoint Handler                        │
│              (llmIntrospect.R)                                      │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  1. Build endpoint documentation structure                  │  │
│  │     • Filter non-hidden endpoints                          │  │
│  │     • Extract parameter metadata                           │  │
│  │     • Categorize by functionality                          │  │
│  │                                                            │  │
│  │  2. Compile API information                                │  │
│  │     • API title, version, description                      │  │
│  │     • Supported networks, protocols, platforms             │  │
│  │     • Usage notes and best practices                       │  │
│  │     • Error code reference                                 │  │
│  │                                                            │  │
│  │  3. Return structured JSON response                        │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          │ JSON Response
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Response Structure                              │
│                                                                     │
│  {                                                                  │
│    "api_info": { ... },          // API metadata                   │
│    "categories": [ ... ],        // 11 functional categories        │
│    "endpoints": [                // 20+ endpoint definitions        │
│      {                                                              │
│        "name": "vaultTrade",                                        │
│        "method": "POST",                                            │
│        "path": "/vaultTrade",                                       │
│        "category": "Trading",                                       │
│        "description": "...",                                        │
│        "parameters": [ ... ]     // Full param specs               │
│      },                                                             │
│      ...                                                            │
│    ],                                                               │
│    "networks": [ ... ],          // Blockchain networks            │
│    "protocols": [ ... ],         // DeFi protocols                 │
│    "platforms": [ ... ],         // Trading platforms              │
│    "usage_notes": [ ... ],       // Best practices                 │
│    "error_codes": [ ... ]        // Error reference                │
│  }                                                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌──────────────┐
│   LLM Query  │
└──────┬───────┘
       │
       │ 1. Request API capabilities
       │
       ▼
┌──────────────────────┐
│  Gateway Middleware  │  ← Rate limiting, logging
└──────┬───────────────┘
       │
       │ 2. Route to llmIntrospect
       │
       ▼
┌────────────────────────────┐
│  llmIntrospectHandler()    │
│                            │
│  • Filter hidden endpoints │
│  • Build documentation     │
│  • Format response         │
└──────┬─────────────────────┘
       │
       │ 3. Return JSON
       │
       ▼
┌──────────────────────┐
│  LLM Processes Docs  │
│                      │
│  • Parse endpoints   │
│  • Validate params   │
│  • Build API calls   │
└──────┬───────────────┘
       │
       │ 4. Execute API operations
       │
       ▼
┌─────────────────────────────┐
│  Other API Endpoints        │
│  (vaultTrade, setBot, etc.) │
└─────────────────────────────┘
```

## Endpoint Categories Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   API Gateway                           │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Asset Management                       │    │
│  │  • approve                                     │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Trading                                │    │
│  │  • vaultTrade                                  │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Automation                             │    │
│  │  • setBot                                      │    │
│  │  • deleteBot                                   │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Market Data                            │    │
│  │  • getCandles                                  │    │
│  │  • getTicks                                    │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         DeFi Lending (Aave V3)                 │    │
│  │  • aaveV3/lend                                 │    │
│  │  • aaveV3/unlend                               │    │
│  │  • aaveV3/borrow                               │    │
│  │  • aaveV3/repay                                │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         CEX Integration                        │    │
│  │  • registerCEXSubaccount                       │    │
│  │  • setCEXSide / getCEXSide                     │    │
│  │  • deleteCEXBot / deactivateCEXBot             │    │
│  │  • deleteCEXSubaccount                         │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Portfolio & Wallet                     │    │
│  │  • poolComposition                             │    │
│  │  • getGasBalance                               │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  ┌────────────────────────────────────────────────┐    │
│  │         Documentation (NEW)                    │    │
│  │  • llmIntrospect  ◄── MCP-style endpoint       │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## File Structure

```
infinite-trading-cloud/
└── infinitetrading/
    └── src/
        └── api/
            ├── helpers/
            │   └── endpoints.R              ← Endpoint registry (MODIFIED)
            │
            └── gateway/
                ├── gateway.R                ← Main router
                ├── IMPLEMENTATION_SUMMARY.md (NEW)
                ├── QUICK_REFERENCE.md       (NEW)
                │
                └── endpoints/
                    ├── llmIntrospect.R                  (NEW) ◄── Core endpoint
                    ├── LLM_INTROSPECT_README.md         (NEW) ◄── Documentation
                    ├── LLM_INTEGRATION_EXAMPLES.md      (NEW) ◄── Examples
                    ├── test_llm_introspect.sh          (NEW) ◄── Test script
                    │
                    ├── vaultTrade.R         ← Trading endpoint
                    ├── approve.R            ← Asset approval
                    ├── setBot.R             ← Bot configuration
                    ├── aaveV3.R             ← DeFi lending
                    └── ... (other endpoints)
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│                Public Internet                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ HTTPS
                       ▼
┌─────────────────────────────────────────────────────────┐
│              Rate Limiting Layer                        │
│              (600 req/min per IP)                       │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│              Endpoint Filtering                         │
│                                                         │
│  ┌─────────────────┐    ┌──────────────────┐          │
│  │ Public Endpoints│    │ Hidden Endpoints │          │
│  │                 │    │                  │          │
│  │ • llmIntrospect │    │ • createGasWallet│          │
│  │ • vaultTrade    │    │ • linkGasWallet  │          │
│  │ • approve       │    │ • getAllBots     │          │
│  │ • setBot        │    │ • getAllGasBalance│         │
│  │ • getCandles    │    │ • setCEXStrategy │          │
│  │ • ...           │    │ • ...            │          │
│  │                 │    │                  │          │
│  │ ✓ In Docs       │    │ ✗ Not in Docs    │          │
│  └─────────────────┘    └──────────────────┘          │
└─────────────────────────────────────────────────────────┘
```

## LLM Interaction Pattern

```
┌──────────────┐
│   AI Agent   │
└──────┬───────┘
       │
       │ Phase 1: Discovery
       ├─────────────────────────────────────┐
       │ GET /llmIntrospect                  │
       └─────────────────────────────────────┘
       │
       │ Receives: Full API documentation
       │
       ▼
┌──────────────────────────┐
│  Parse & Understand      │
│                          │
│  • Available endpoints   │
│  • Required parameters   │
│  • Supported networks    │
│  • Usage constraints     │
└──────┬───────────────────┘
       │
       │ Phase 2: Planning
       ├─────────────────────────────────────┐
       │ • Identify relevant endpoints       │
       │ • Validate user requirements        │
       │ • Check parameter constraints       │
       └─────────────────────────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Construct API Call      │
│                          │
│  • Select endpoint       │
│  • Build parameters      │
│  • Validate inputs       │
└──────┬───────────────────┘
       │
       │ Phase 3: Execution
       ├─────────────────────────────────────┐
       │ POST /vaultTrade (or other)         │
       │ { apiKey, pool, network, ... }      │
       └─────────────────────────────────────┘
       │
       ▼
┌──────────────────────────┐
│  Handle Response         │
│                          │
│  • Success: Report result│
│  • Error: Interpret &    │
│    provide guidance      │
└──────────────────────────┘
```

## Deployment Flow

```
1. Code Changes
   └─> Add llmIntrospect to endpoints array
   └─> Create llmIntrospect.R endpoint file

2. Gateway Startup (gateway.R)
   └─> Load endpoints from endpoints.R
   └─> For each endpoint in array:
       └─> Call add_endpoint(name, pr)
           └─> Source endpoint file
           └─> Register handler with Plumber

3. Runtime
   └─> Endpoint available at GET /llmIntrospect
   └─> Visible in Swagger docs
   └─> Rate limited by middleware
   └─> Logged by postroute hook

4. LLM Access
   └─> Query endpoint anytime
   └─> No authentication required
   └─> Receive current API state
```

---

This architecture enables self-documenting API capabilities that LLMs can discover and utilize autonomously.
