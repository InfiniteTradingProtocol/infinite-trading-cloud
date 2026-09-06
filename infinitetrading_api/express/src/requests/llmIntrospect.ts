/**
 * requests/llmIntrospect.ts — Node port of the R gateway's llmIntrospect.R
 * (port 8003). This endpoint is pure static documentation: the R handler built
 * a large literal list and returned it, touching no database, no chain, and no
 * other service. There is therefore no logic to re-derive — only a payload to
 * reproduce exactly.
 *
 * PARITY METHOD: the constant below was generated mechanically from the live
 * production response of the R gateway (`curl http://localhost:8003/llmIntrospect`)
 * captured immediately before this migration, so it is byte-equivalent by
 * construction rather than by hand-transcription of the 441-line R literal.
 * That includes plumber/jsonlite's scalar boxing (every scalar is a 1-element
 * array, e.g. "version":["1.0.0"]) and the nesting of `parameters`,
 * `subroutes`, `categories`, `platforms` and `error_codes`.
 *
 * KNOWN INACCURACIES IN THE DOCUMENT ITSELF — deliberately preserved, because
 * this endpoint's contract is "what the R gateway served" and changing the text
 * would alter what LLM consumers have been indexing:
 *   - The CEX entries document an `apiKey`/`subaccountId`/`apiSecret` parameter
 *     shape that the real CEX endpoints never used (they take
 *     gas_wallet_api_key + subaccount_name, or manager + signature).
 *   - deleteCEXBot and deleteCEXSubaccount are listed as POST; both are in fact
 *     DELETE.
 *   - The list omits several live endpoints (getAllBots, linkGasWallet,
 *     addLiquidity, removeLiquidity, ...) and pre-dates mintManagerFeeBatch.
 * These are documentation defects, not behavioural ones, so they are reported
 * here rather than silently corrected during a migration.
 *
 * RATE LIMITING: this route sits behind `llmIntrospectRateLimiter`
 * (10 req/60s per IP), already wired in src/index.ts as
 * `app.use('/llmIntrospect', llmIntrospectRateLimiter)` ahead of the default
 * 600/60s bucket — matching R gateway.R's separate stricter counter.
 * Registering the route here does not change that wiring.
 *
 * SWAGGER: not annotated with @openapi — R served this as documentation for
 * LLM agents rather than as part of the published API surface.
 */

import { Router, Request, Response } from 'express';

const router = Router();

/** Exact payload served by the R gateway (jsonlite boxed wire format). */
const LLM_INTROSPECT_DOC = {
    "api_info": {
      "title": [
        "Infinite Trading Protocol API"
      ],
      "version": [
        "1.0.0"
      ],
      "description": [
        "Deploy automated trading strategies in DeFi without managing Web3 infrastructure. This API provides endpoints for vault management, automated trading, DeFi protocol interactions (Aave, dHEDGE), and CEX integration."
      ],
      "base_url": [
        "https://api.infinitetrading.io"
      ],
      "documentation": [
        "https://www.infinitetrading.io/docs"
      ],
      "authentication": [
        "All endpoints require an API key. Generate keys at https://www.infinitetrading.io/managers"
      ]
    },
    "categories": [
      {
        "name": [
          "Asset Management"
        ],
        "description": [
          "Approve and manage assets for trading and DeFi operations"
        ]
      },
      {
        "name": [
          "Trading"
        ],
        "description": [
          "Execute trades within vault pools across multiple DEXs"
        ]
      },
      {
        "name": [
          "Automation"
        ],
        "description": [
          "Configure and manage automated trading bots"
        ]
      },
      {
        "name": [
          "Market Data"
        ],
        "description": [
          "Access historical and real-time market data"
        ]
      },
      {
        "name": [
          "Portfolio"
        ],
        "description": [
          "Query portfolio composition and asset allocations"
        ]
      },
      {
        "name": [
          "Wallet"
        ],
        "description": [
          "Manage gas wallets and check balances"
        ]
      },
      {
        "name": [
          "Blockchain"
        ],
        "description": [
          "Interact with blockchain contracts and tokens"
        ]
      },
      {
        "name": [
          "DeFi Lending"
        ],
        "description": [
          "Lend, borrow, and manage positions on Aave V3"
        ]
      },
      {
        "name": [
          "Authentication"
        ],
        "description": [
          "Generate and manage API keys"
        ]
      },
      {
        "name": [
          "Pool Management"
        ],
        "description": [
          "Manage pool fees and configurations"
        ]
      },
      {
        "name": [
          "CEX Integration"
        ],
        "description": [
          "Integrate with centralized exchanges for automated trading"
        ]
      }
    ],
    "endpoints": [
      {
        "name": [
          "approve"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/approve"
        ],
        "category": [
          "Asset Management"
        ],
        "description": [
          "Approve assets for trading or lending/borrowing within a pool. Required before executing trades or DeFi operations. For short positions, enable BTC1XBEAR or ETH1XBEAR (Optimism/Arbitrum only)."
        ],
        "gas_cost": {
          "estimated_gas": [
            "50,000-100,000 gas units"
          ],
          "estimated_cost_usd": [
            "$0.01-0.05"
          ],
          "note": [
            "One-time approval per asset per platform"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Ethereum Layer 2 network (Base, Optimism, Polygon, Arbitrum)"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use (e.g., dhedge)"
            ],
            "default": [
              "dhedge"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address or identifier"
            ]
          },
          {
            "name": [
              "asset"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Asset to approve (symbol or contract address, e.g., USDC)"
            ]
          },
          {
            "name": [
              "platform"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Platform for execution (odos for swaps, aave for lending)"
            ],
            "default": [
              "odos"
            ]
          }
        ]
      },
      {
        "name": [
          "vaultTrade"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/vaultTrade"
        ],
        "category": [
          "Trading"
        ],
        "description": [
          "Execute trades inside a specific pool on the specified protocol and network. Supports custom slippage, share percentage, and amount parameters. If amount exceeds vault balance, uses maximum available."
        ],
        "gas_cost": {
          "estimated_gas": [
            "200,000-500,000 gas units"
          ],
          "estimated_cost_usd": [
            "$0.05-0.20"
          ],
          "note": [
            "Varies based on trade complexity and DEX routing"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use"
            ],
            "default": [
              "dhedge"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool to target"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ],
            "default": [
              "optimism"
            ]
          },
          {
            "name": [
              "from"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Asset to sell"
            ]
          },
          {
            "name": [
              "to"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Asset to buy"
            ]
          },
          {
            "name": [
              "amount"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Maximum USD amount to buy (overrides share parameter)"
            ],
            "default": [
              "NA"
            ]
          },
          {
            "name": [
              "slippage"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Slippage percentage"
            ],
            "default": [
              0.5
            ]
          },
          {
            "name": [
              "share"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Share percentage (1-100)"
            ],
            "default": [
              100
            ]
          },
          {
            "name": [
              "platform"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Platform to use"
            ],
            "default": [
              "odos"
            ]
          }
        ]
      },
      {
        "name": [
          "setBot"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/setBot"
        ],
        "category": [
          "Automation"
        ],
        "description": [
          "Configure an automated trading bot with strategy sides (long, short, hold, neutral). Long buys all assets, short sells all, neutral converts to USDC, hold maintains positions. Supports lending integration and customizable thresholds."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (configuration only)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "Bot execution incurs gas costs per trade based on strategy"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use"
            ],
            "default": [
              "dhedge"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ]
          },
          {
            "name": [
              "pair"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Trading pair to monitor"
            ]
          },
          {
            "name": [
              "side"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Strategy side: long, short, hold, or neutral"
            ]
          },
          {
            "name": [
              "threshold"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Strategy threshold"
            ],
            "default": [
              1
            ]
          },
          {
            "name": [
              "max_usd"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Maximum USD amount per trade"
            ],
            "default": [
              10000000
            ]
          },
          {
            "name": [
              "slippage"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Slippage tolerance percentage"
            ],
            "default": [
              1
            ]
          },
          {
            "name": [
              "share"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Share percentage (1-100)"
            ],
            "default": [
              100
            ]
          },
          {
            "name": [
              "platform"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Trading platform"
            ],
            "default": [
              "odos"
            ]
          },
          {
            "name": [
              "lending"
            ],
            "type": [
              "boolean"
            ],
            "required": [
              false
            ],
            "description": [
              "Enable lending integration"
            ],
            "default": [
              false
            ]
          }
        ]
      },
      {
        "name": [
          "deleteBot"
        ],
        "method": [
          "DELETE"
        ],
        "path": [
          "/deleteBot"
        ],
        "category": [
          "Automation"
        ],
        "description": [
          "Turn off and delete the automated trading bot for a specific pool. Stops all automated trading activities."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (configuration only)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "No blockchain transaction required"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ]
          }
        ]
      },
      {
        "name": [
          "getCandles"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getCandles"
        ],
        "category": [
          "Market Data"
        ],
        "description": [
          "Fetch historical price candles from exchanges. Supports multiple pairs and timeframes from Coinbase (BTC-USD, ETH-USD, VELO-USD, POL-USD, OP-USD, SOL-USD, LINK-USD, ARB-USD, AERO-USD)."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (read-only)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "No blockchain transaction required"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "exchange"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Exchange name"
            ],
            "default": [
              "coinbase"
            ]
          },
          {
            "name": [
              "timeframe"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Candle timeframe"
            ],
            "default": [
              "6h"
            ]
          },
          {
            "name": [
              "pair"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Trading pair"
            ],
            "default": [
              "BTC-USD"
            ]
          },
          {
            "name": [
              "bars_back"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Number of historical bars"
            ],
            "default": [
              200
            ]
          }
        ]
      },
      {
        "name": [
          "getTicks"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getTicks"
        ],
        "category": [
          "Market Data"
        ],
        "description": [
          "Get real-time tick data for trading pairs."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "pair"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Trading pair"
            ]
          },
          {
            "name": [
              "exchange"
            ],
            "type": [
              "string"
            ],
            "required": [
              false
            ],
            "description": [
              "Exchange name"
            ]
          }
        ]
      },
      {
        "name": [
          "poolComposition"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/poolComposition"
        ],
        "category": [
          "Portfolio"
        ],
        "description": [
          "Get detailed composition and asset allocation of a pool, including token balances and percentages."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (read-only)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "No blockchain transaction required"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to query"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ]
          }
        ]
      },
      {
        "name": [
          "getGasBalance"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getGasBalance"
        ],
        "category": [
          "Wallet"
        ],
        "description": [
          "Check gas balance (native token) of a gas wallet on a specific network."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (read-only)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "No blockchain transaction required"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to check"
            ]
          }
        ]
      },
      {
        "name": [
          "getContract"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getContract"
        ],
        "category": [
          "Blockchain"
        ],
        "description": [
          "Get contract address for a specific token on a network."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "token"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Token symbol"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to query"
            ]
          }
        ]
      },
      {
        "name": [
          "getSymbol"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getSymbol"
        ],
        "category": [
          "Blockchain"
        ],
        "description": [
          "Get token symbol from a contract address on a specific network."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "contract"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Contract address"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to query"
            ]
          }
        ]
      },
      {
        "name": [
          "aaveV3"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/aaveV3"
        ],
        "category": [
          "DeFi Lending"
        ],
        "description": [
          "Comprehensive Aave V3 protocol integration providing lending, borrowing, withdrawal, and repayment operations. Sub-routes include /lend, /unlend, /borrow, /repay, /getBorrowed, /getSupplied, and /getHealthFactor for full DeFi lending management."
        ],
        "gas_cost": {
          "estimated_gas": [
            "150,000-400,000 gas units"
          ],
          "estimated_cost_usd": [
            "$0.03-0.15"
          ],
          "note": [
            "Varies by operation: lend/unlend/borrow/repay have different costs"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use"
            ],
            "default": [
              "dhedge"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address"
            ]
          },
          {
            "name": [
              "asset"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Asset symbol or contract address"
            ]
          },
          {
            "name": [
              "share"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Percentage of asset (1-100)"
            ],
            "default": [
              100
            ]
          },
          {
            "name": [
              "amount"
            ],
            "type": [
              "number"
            ],
            "required": [
              false
            ],
            "description": [
              "Fixed amount (overrides share)"
            ],
            "default": [
              0
            ]
          }
        ],
        "subroutes": [
          [
            "/lend - Supply assets to Aave for lending"
          ],
          [
            "/unlend - Withdraw supplied assets from Aave"
          ],
          [
            "/borrow - Borrow assets against collateral"
          ],
          [
            "/repay - Repay borrowed assets"
          ],
          [
            "/getBorrowed - Get borrowed amount for an asset"
          ],
          [
            "/getSupplied - Get supplied amount for an asset"
          ],
          [
            "/getHealthFactor - Get account health factor"
          ]
        ]
      },
      {
        "name": [
          "getNewApiKey"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/getNewApiKey"
        ],
        "category": [
          "Authentication"
        ],
        "description": [
          "Generate a new API key for a gas wallet. Requires existing authentication."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Existing API key for authentication"
            ]
          },
          {
            "name": [
              "gasWallet"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Gas wallet address"
            ]
          }
        ]
      },
      {
        "name": [
          "mintManagerFee"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/mintManagerFee"
        ],
        "category": [
          "Pool Management"
        ],
        "description": [
          "Mint manager fees from a pool. Used by pool managers to claim their management fees."
        ],
        "gas_cost": {
          "estimated_gas": [
            "100,000-200,000 gas units"
          ],
          "estimated_cost_usd": [
            "$0.02-0.08"
          ],
          "note": [
            "Mints performance and management fees to manager address"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "protocol"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Protocol to use"
            ]
          },
          {
            "name": [
              "pool"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Pool address"
            ]
          },
          {
            "name": [
              "network"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Network to use"
            ]
          }
        ]
      },
      {
        "name": [
          "registerCEXSubaccount"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/registerCEXSubaccount"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Register a centralized exchange (CEX) subaccount for API-based trading."
        ],
        "gas_cost": {
          "estimated_gas": [
            "N/A (off-chain)"
          ],
          "estimated_cost_usd": [
            "$0.00"
          ],
          "note": [
            "CEX operations are off-chain, no gas required"
          ]
        },
        "rate_limit": [
          "600 requests/minute per IP"
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "exchange"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Exchange name"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          },
          {
            "name": [
              "apiSecret"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Exchange API secret"
            ]
          }
        ]
      },
      {
        "name": [
          "setCEXSide"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/setCEXSide"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Set trading side (long/short) for a CEX subaccount."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          },
          {
            "name": [
              "side"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Trading side (long/short)"
            ]
          }
        ]
      },
      {
        "name": [
          "getCEXSide"
        ],
        "method": [
          "GET"
        ],
        "path": [
          "/getCEXSide"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Get current trading side configuration for a CEX subaccount."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          }
        ]
      },
      {
        "name": [
          "deleteCEXBot"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/deleteCEXBot"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Delete an automated trading bot on a CEX subaccount."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          }
        ]
      },
      {
        "name": [
          "deactivateCEXBot"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/deactivateCEXBot"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Temporarily deactivate a CEX trading bot without deleting it."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          }
        ]
      },
      {
        "name": [
          "deleteCEXSubaccount"
        ],
        "method": [
          "POST"
        ],
        "path": [
          "/deleteCEXSubaccount"
        ],
        "category": [
          "CEX Integration"
        ],
        "description": [
          "Remove a registered CEX subaccount from the system."
        ],
        "parameters": [
          {
            "name": [
              "apiKey"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "API key for authentication"
            ]
          },
          {
            "name": [
              "subaccountId"
            ],
            "type": [
              "string"
            ],
            "required": [
              true
            ],
            "description": [
              "Subaccount identifier"
            ]
          }
        ]
      }
    ],
    "networks": [
      [
        "Optimism"
      ],
      [
        "Base"
      ],
      [
        "Arbitrum"
      ],
      [
        "Polygon"
      ]
    ],
    "protocols": [
      [
        "dHEDGE"
      ],
      [
        "Aave V3"
      ],
      [
        "Uniswap"
      ],
      [
        "Velodrome"
      ]
    ],
    "platforms": [
      {
        "name": [
          "odos"
        ],
        "type": [
          "DEX Aggregator"
        ],
        "use_case": [
          "Optimal swap routing"
        ]
      },
      {
        "name": [
          "aave"
        ],
        "type": [
          "Lending Protocol"
        ],
        "use_case": [
          "Lending and borrowing"
        ]
      }
    ],
    "rate_limits": {
      "default": [
        "600 requests/minute per IP"
      ],
      "llmIntrospect": [
        "10 requests/minute per IP (strict limit to prevent abuse)"
      ],
      "note": [
        "Rate limits are per-endpoint and per-IP. Exceeding limits returns HTTP 429."
      ]
    },
    "usage_notes": [
      [
        "Always approve assets before trading or lending operations"
      ],
      [
        "API keys are required for all endpoints and can be generated at the manager dashboard"
      ],
      [
        "Gas costs vary by network congestion and are estimates only"
      ],
      [
        "For short positions, enable leveraged bear tokens (BTC1XBEAR/ETH1XBEAR) on supported networks"
      ],
      [
        "When amount parameter is specified in trades, it overrides the share parameter"
      ],
      [
        "All responses follow a consistent structure with status, status_code, and message fields"
      ],
      [
        "Read-only endpoints (GET) have no gas costs; write operations (POST/DELETE) incur gas fees"
      ]
    ],
    "error_codes": [
      {
        "code": [
          200
        ],
        "description": [
          "Success"
        ]
      },
      {
        "code": [
          400
        ],
        "description": [
          "Bad request - invalid parameters"
        ]
      },
      {
        "code": [
          401
        ],
        "description": [
          "Unauthorized - invalid API key"
        ]
      },
      {
        "code": [
          429
        ],
        "description": [
          "Rate limit exceeded"
        ]
      },
      {
        "code": [
          500
        ],
        "description": [
          "Internal server error"
        ]
      },
      {
        "code": [
          1007
        ],
        "description": [
          "Invalid share parameter (must be 1-100)"
        ]
      }
    ]
  } as const;

router.get('/llmIntrospect', (_req: Request, res: Response) => {
  // R wrapped the body in tryCatch and returned
  // {status:"error", message:"Failed to generate API introspection: ..."} on
  // error. Serving a frozen constant cannot throw, so that branch is
  // unreachable here; the shape is documented for completeness only.
  return res.json(LLM_INTROSPECT_DOC);
});

export default router;
