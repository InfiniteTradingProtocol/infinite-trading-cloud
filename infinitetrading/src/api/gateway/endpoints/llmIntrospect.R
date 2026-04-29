######################################################################
#* LLM Introspection Endpoint (MCP-style)
#* This endpoint provides API documentation for LLMs
#* Returns only non-hidden endpoints with their metadata
#* 
#* @response 200 Returns comprehensive API documentation including endpoints, parameters, and descriptions
#* @response 500 Internal server error
#* @tag Documentation
#* @get /llmIntrospect
######################################################################

llmIntrospectHandler <- function() {
  tryCatch({
    # Get the plumber router object to extract endpoint information
    # We'll build a comprehensive documentation structure
    
    # Define non-hidden endpoints with their descriptions
    endpoint_docs <- list(
      list(
        name = "approve",
        method = "POST",
        path = "/approve",
        category = "Asset Management",
        description = "Approve assets for trading or lending/borrowing within a pool. Required before executing trades or DeFi operations. For short positions, enable BTC1XBEAR or ETH1XBEAR (Optimism/Arbitrum only).",
        gas_cost = list(
          estimated_gas = "50,000-100,000 gas units",
          estimated_cost_usd = "$0.01-0.05",
          note = "One-time approval per asset per platform"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "network", type = "string", required = TRUE, description = "Ethereum Layer 2 network (Base, Optimism, Polygon, Arbitrum)"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use (e.g., dhedge)", default = "dhedge"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address or identifier"),
          list(name = "asset", type = "string", required = TRUE, description = "Asset to approve (symbol or contract address, e.g., USDC)"),
          list(name = "platform", type = "string", required = TRUE, description = "Platform for execution (odos for swaps, aave for lending)", default = "odos")
        )
      ),
      list(
        name = "vaultTrade",
        method = "POST",
        path = "/vaultTrade",
        category = "Trading",
        description = "Execute trades inside a specific pool on the specified protocol and network. Supports custom slippage, share percentage, and amount parameters. If amount exceeds vault balance, uses maximum available.",
        gas_cost = list(
          estimated_gas = "200,000-500,000 gas units",
          estimated_cost_usd = "$0.05-0.20",
          note = "Varies based on trade complexity and DEX routing"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use", default = "dhedge"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool to target"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use", default = "optimism"),
          list(name = "from", type = "string", required = TRUE, description = "Asset to sell"),
          list(name = "to", type = "string", required = TRUE, description = "Asset to buy"),
          list(name = "amount", type = "number", required = FALSE, description = "Maximum USD amount to buy (overrides share parameter)", default = "NA"),
          list(name = "slippage", type = "number", required = FALSE, description = "Slippage percentage", default = 0.5),
          list(name = "share", type = "number", required = FALSE, description = "Share percentage (1-100)", default = 100),
          list(name = "platform", type = "string", required = FALSE, description = "Platform to use", default = "odos")
        )
      ),
      list(
        name = "setBot",
        method = "POST",
        path = "/setBot",
        category = "Automation",
        description = "Configure an automated trading bot with strategy sides (long, short, hold, neutral). Long buys all assets, short sells all, neutral converts to USDC, hold maintains positions. Supports lending integration and customizable thresholds.",
        gas_cost = list(
          estimated_gas = "N/A (configuration only)",
          estimated_cost_usd = "$0.00",
          note = "Bot execution incurs gas costs per trade based on strategy"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use", default = "dhedge"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use"),
          list(name = "pair", type = "string", required = TRUE, description = "Trading pair to monitor"),
          list(name = "side", type = "string", required = TRUE, description = "Strategy side: long, short, hold, or neutral"),
          list(name = "threshold", type = "number", required = FALSE, description = "Strategy threshold", default = 1),
          list(name = "max_usd", type = "number", required = FALSE, description = "Maximum USD amount per trade", default = 10000000),
          list(name = "slippage", type = "number", required = FALSE, description = "Slippage tolerance percentage", default = 1),
          list(name = "share", type = "number", required = FALSE, description = "Share percentage (1-100)", default = 100),
          list(name = "platform", type = "string", required = FALSE, description = "Trading platform", default = "odos"),
          list(name = "lending", type = "boolean", required = FALSE, description = "Enable lending integration", default = FALSE)
        )
      ),
      list(
        name = "deleteBot",
        method = "DELETE",
        path = "/deleteBot",
        category = "Automation",
        description = "Turn off and delete the automated trading bot for a specific pool. Stops all automated trading activities.",
        gas_cost = list(
          estimated_gas = "N/A (configuration only)",
          estimated_cost_usd = "$0.00",
          note = "No blockchain transaction required"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use")
        )
      ),
      list(
        name = "getCandles",
        method = "GET",
        path = "/getCandles",
        category = "Market Data",
        description = "Fetch historical price candles from exchanges. Supports multiple pairs and timeframes from Coinbase (BTC-USD, ETH-USD, VELO-USD, POL-USD, OP-USD, SOL-USD, LINK-USD, ARB-USD, AERO-USD).",
        gas_cost = list(
          estimated_gas = "N/A (read-only)",
          estimated_cost_usd = "$0.00",
          note = "No blockchain transaction required"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "exchange", type = "string", required = FALSE, description = "Exchange name", default = "coinbase"),
          list(name = "timeframe", type = "string", required = FALSE, description = "Candle timeframe", default = "6h"),
          list(name = "pair", type = "string", required = FALSE, description = "Trading pair", default = "BTC-USD"),
          list(name = "bars_back", type = "number", required = FALSE, description = "Number of historical bars", default = 200)
        )
      ),
      list(
        name = "getTicks",
        method = "GET",
        path = "/getTicks",
        category = "Market Data",
        description = "Get real-time tick data for trading pairs.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "pair", type = "string", required = TRUE, description = "Trading pair"),
          list(name = "exchange", type = "string", required = FALSE, description = "Exchange name")
        )
      ),
      list(
        name = "poolComposition",
        method = "GET",
        path = "/poolComposition",
        category = "Portfolio",
        description = "Get detailed composition and asset allocation of a pool, including token balances and percentages.",
        gas_cost = list(
          estimated_gas = "N/A (read-only)",
          estimated_cost_usd = "$0.00",
          note = "No blockchain transaction required"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to query"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use")
        )
      ),
      list(
        name = "getGasBalance",
        method = "GET",
        path = "/getGasBalance",
        category = "Wallet",
        description = "Check gas balance (native token) of a gas wallet on a specific network.",
        gas_cost = list(
          estimated_gas = "N/A (read-only)",
          estimated_cost_usd = "$0.00",
          note = "No blockchain transaction required"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "network", type = "string", required = TRUE, description = "Network to check")
        )
      ),
      list(
        name = "getContract",
        method = "GET",
        path = "/getContract",
        category = "Blockchain",
        description = "Get contract address for a specific token on a network.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "token", type = "string", required = TRUE, description = "Token symbol"),
          list(name = "network", type = "string", required = TRUE, description = "Network to query")
        )
      ),
      list(
        name = "getSymbol",
        method = "GET",
        path = "/getSymbol",
        category = "Blockchain",
        description = "Get token symbol from a contract address on a specific network.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "contract", type = "string", required = TRUE, description = "Contract address"),
          list(name = "network", type = "string", required = TRUE, description = "Network to query")
        )
      ),
      list(
        name = "aaveV3",
        method = "POST",
        path = "/aaveV3",
        category = "DeFi Lending",
        description = "Comprehensive Aave V3 protocol integration providing lending, borrowing, withdrawal, and repayment operations. Sub-routes include /lend, /unlend, /borrow, /repay, /getBorrowed, /getSupplied, and /getHealthFactor for full DeFi lending management.",
        gas_cost = list(
          estimated_gas = "150,000-400,000 gas units",
          estimated_cost_usd = "$0.03-0.15",
          note = "Varies by operation: lend/unlend/borrow/repay have different costs"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use", default = "dhedge"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address"),
          list(name = "asset", type = "string", required = TRUE, description = "Asset symbol or contract address"),
          list(name = "share", type = "number", required = FALSE, description = "Percentage of asset (1-100)", default = 100),
          list(name = "amount", type = "number", required = FALSE, description = "Fixed amount (overrides share)", default = 0)
        ),
        subroutes = list(
          "/lend - Supply assets to Aave for lending",
          "/unlend - Withdraw supplied assets from Aave",
          "/borrow - Borrow assets against collateral",
          "/repay - Repay borrowed assets",
          "/getBorrowed - Get borrowed amount for an asset",
          "/getSupplied - Get supplied amount for an asset",
          "/getHealthFactor - Get account health factor"
        )
      ),
      list(
        name = "getNewApiKey",
        method = "POST",
        path = "/getNewApiKey",
        category = "Authentication",
        description = "Generate a new API key for a gas wallet. Requires existing authentication.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "Existing API key for authentication"),
          list(name = "gasWallet", type = "string", required = TRUE, description = "Gas wallet address")
        )
      ),
      list(
        name = "mintManagerFee",
        method = "POST",
        path = "/mintManagerFee",
        category = "Pool Management",
        description = "Mint manager fees from a pool. Used by pool managers to claim their management fees.",
        gas_cost = list(
          estimated_gas = "100,000-200,000 gas units",
          estimated_cost_usd = "$0.02-0.08",
          note = "Mints performance and management fees to manager address"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "protocol", type = "string", required = TRUE, description = "Protocol to use"),
          list(name = "pool", type = "string", required = TRUE, description = "Pool address"),
          list(name = "network", type = "string", required = TRUE, description = "Network to use")
        )
      ),
      list(
        name = "registerCEXSubaccount",
        method = "POST",
        path = "/registerCEXSubaccount",
        category = "CEX Integration",
        description = "Register a centralized exchange (CEX) subaccount for API-based trading.",
        gas_cost = list(
          estimated_gas = "N/A (off-chain)",
          estimated_cost_usd = "$0.00",
          note = "CEX operations are off-chain, no gas required"
        ),
        rate_limit = "600 requests/minute per IP",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "exchange", type = "string", required = TRUE, description = "Exchange name"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier"),
          list(name = "apiSecret", type = "string", required = TRUE, description = "Exchange API secret")
        )
      ),
      list(
        name = "setCEXSide",
        method = "POST",
        path = "/setCEXSide",
        category = "CEX Integration",
        description = "Set trading side (long/short) for a CEX subaccount.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier"),
          list(name = "side", type = "string", required = TRUE, description = "Trading side (long/short)")
        )
      ),
      list(
        name = "getCEXSide",
        method = "GET",
        path = "/getCEXSide",
        category = "CEX Integration",
        description = "Get current trading side configuration for a CEX subaccount.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier")
        )
      ),
      list(
        name = "deleteCEXBot",
        method = "POST",
        path = "/deleteCEXBot",
        category = "CEX Integration",
        description = "Delete an automated trading bot on a CEX subaccount.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier")
        )
      ),
      list(
        name = "deactivateCEXBot",
        method = "POST",
        path = "/deactivateCEXBot",
        category = "CEX Integration",
        description = "Temporarily deactivate a CEX trading bot without deleting it.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier")
        )
      ),
      list(
        name = "deleteCEXSubaccount",
        method = "POST",
        path = "/deleteCEXSubaccount",
        category = "CEX Integration",
        description = "Remove a registered CEX subaccount from the system.",
        parameters = list(
          list(name = "apiKey", type = "string", required = TRUE, description = "API key for authentication"),
          list(name = "subaccountId", type = "string", required = TRUE, description = "Subaccount identifier")
        )
      )
    )
    
    # Build the response structure optimized for LLMs
    response <- list(
      api_info = list(
        title = "Infinite Trading Protocol API",
        version = "1.0.0",
        description = "Deploy automated trading strategies in DeFi without managing Web3 infrastructure. This API provides endpoints for vault management, automated trading, DeFi protocol interactions (Aave, dHEDGE), and CEX integration.",
        base_url = "https://api.infinitetrading.io",
        documentation = "https://www.infinitetrading.io/docs",
        authentication = "All endpoints require an API key. Generate keys at https://www.infinitetrading.io/managers"
      ),
      categories = list(
        list(
          name = "Asset Management",
          description = "Approve and manage assets for trading and DeFi operations"
        ),
        list(
          name = "Trading",
          description = "Execute trades within vault pools across multiple DEXs"
        ),
        list(
          name = "Automation",
          description = "Configure and manage automated trading bots"
        ),
        list(
          name = "Market Data",
          description = "Access historical and real-time market data"
        ),
        list(
          name = "Portfolio",
          description = "Query portfolio composition and asset allocations"
        ),
        list(
          name = "Wallet",
          description = "Manage gas wallets and check balances"
        ),
        list(
          name = "Blockchain",
          description = "Interact with blockchain contracts and tokens"
        ),
        list(
          name = "DeFi Lending",
          description = "Lend, borrow, and manage positions on Aave V3"
        ),
        list(
          name = "Authentication",
          description = "Generate and manage API keys"
        ),
        list(
          name = "Pool Management",
          description = "Manage pool fees and configurations"
        ),
        list(
          name = "CEX Integration",
          description = "Integrate with centralized exchanges for automated trading"
        )
      ),
      endpoints = endpoint_docs,
      networks = list("Optimism", "Base", "Arbitrum", "Polygon"),
      protocols = list("dHEDGE", "Aave V3", "Uniswap", "Velodrome"),
      platforms = list(
        list(name = "odos", type = "DEX Aggregator", use_case = "Optimal swap routing"),
        list(name = "aave", type = "Lending Protocol", use_case = "Lending and borrowing")
      ),
      rate_limits = list(
        default = "600 requests/minute per IP",
        llmIntrospect = "10 requests/minute per IP (strict limit to prevent abuse)",
        note = "Rate limits are per-endpoint and per-IP. Exceeding limits returns HTTP 429."
      ),
      usage_notes = list(
        "Always approve assets before trading or lending operations",
        "API keys are required for all endpoints and can be generated at the manager dashboard",
        "Gas costs vary by network congestion and are estimates only",
        "For short positions, enable leveraged bear tokens (BTC1XBEAR/ETH1XBEAR) on supported networks",
        "When amount parameter is specified in trades, it overrides the share parameter",
        "All responses follow a consistent structure with status, status_code, and message fields",
        "Read-only endpoints (GET) have no gas costs; write operations (POST/DELETE) incur gas fees"
      ),
      error_codes = list(
        list(code = 200, description = "Success"),
        list(code = 400, description = "Bad request - invalid parameters"),
        list(code = 401, description = "Unauthorized - invalid API key"),
        list(code = 429, description = "Rate limit exceeded"),
        list(code = 500, description = "Internal server error"),
        list(code = 1007, description = "Invalid share parameter (must be 1-100)")
      )
    )
    
    return(response)
    
  }, error = function(e) {
    return(list(
      status = "error",
      message = paste("Failed to generate API introspection:", e$message)
    ))
  })
}

# Register the endpoint
pr$handle("GET", "/llmIntrospect", llmIntrospectHandler,
  comment = "MCP-style endpoint that provides comprehensive API documentation for LLMs. Returns structured information about all non-hidden endpoints, their parameters, categories, and usage guidelines. Designed for AI agents to understand and interact with the Infinite Trading API."
)
