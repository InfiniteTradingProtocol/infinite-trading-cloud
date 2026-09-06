/**
 * openapiComponents.ts — reusable OpenAPI parameter/schema definitions.
 *
 * Centralising these gives the Swagger UI real dropdowns (via `enum`) and
 * sensible `default`s instead of free-text boxes, and — more importantly —
 * means the documented set of networks/protocols/platforms is defined once
 * rather than copy-pasted into ~45 endpoint annotations where it would
 * inevitably drift.
 *
 * Referenced from JSDoc annotations as:
 *   $ref: '#/components/parameters/NetworkParam'
 */

/**
 * Networks accepted by the API. Mirrors the `networks` table.
 * (`mainnet` is a legacy synonym for `ethereum`; kept because callers use it.)
 */
export const NETWORKS = [
  'base',
  'optimism',
  'arbitrum',
  'polygon',
  'ethereum',
  'mainnet',
  'hyperliquid',
] as const;

/**
 * Vault protocols. `chamber` is the current brand name for `dhedge` and is
 * normalized to it in middleware (see protocolAlias.ts), so both are valid.
 */
export const PROTOCOLS = ['dhedge', 'chamber', 'defund'] as const;

/**
 * DEX/lending platforms exposed in the docs.
 * `auto` is the default and means "let the executor pick the best DEX".
 * Deprecated aliases (notably `odos`) are still accepted by the API but are
 * intentionally omitted here so nobody adopts them in new integrations.
 */
export const PLATFORMS = [
  'auto',
  'uniswapV3',
  'velodrome',
  'velodromecl',
  'aerodrome',
  'aerodromecl',
  'pancakecl',
  'quickswap',
  'kyberswap',
  'cowswap',
  'pendle',
  'aavev3',
  'compoundv3',
  'fluid',
  'lyra',
  'hyperliquid',
] as const;

/** Lending-only platforms, for the lend/unlend/borrow/repay family. */
export const LENDING_PLATFORMS = ['aavev3', 'compoundv3', 'fluid'] as const;

export const openapiComponents = {
  parameters: {
    ApiKeyParam: {
      in: 'query',
      name: 'apiKey',
      required: true,
      description: 'Your Infinite Trading API key (UUID).',
      schema: { type: 'string', format: 'uuid' },
    },
    NetworkParam: {
      in: 'query',
      name: 'network',
      required: true,
      description: 'Chain the vault lives on.',
      schema: { type: 'string', enum: [...NETWORKS], default: 'base' },
    },
    ProtocolParam: {
      in: 'query',
      name: 'protocol',
      required: false,
      description:
        'Vault protocol. `chamber` is the current name for `dhedge`; both are accepted.',
      schema: { type: 'string', enum: [...PROTOCOLS], default: 'dhedge' },
    },
    PoolParam: {
      in: 'query',
      name: 'pool',
      required: true,
      description: 'Vault (pool) contract address.',
      schema: { type: 'string', pattern: '^0x[a-fA-F0-9]{40}$' },
    },
    PlatformParam: {
      in: 'query',
      name: 'platform',
      required: false,
      description:
        'Execution venue. `auto` (default) lets the executor pick the best available DEX.',
      schema: { type: 'string', enum: [...PLATFORMS], default: 'auto' },
    },
    LendingPlatformParam: {
      in: 'query',
      name: 'platform',
      required: false,
      description: 'Lending protocol to use.',
      schema: { type: 'string', enum: [...LENDING_PLATFORMS], default: 'aavev3' },
    },
    AssetParam: {
      in: 'query',
      name: 'asset',
      required: true,
      description: 'Asset symbol (e.g. USDC, WETH) or contract address.',
      schema: { type: 'string' },
    },
    ShareParam: {
      in: 'query',
      name: 'share',
      required: false,
      description:
        'Percentage (0-100) of the available balance to use. Takes precedence over `amount` if both are given.',
      schema: { type: 'number', minimum: 0, maximum: 100 },
    },
    AmountParam: {
      in: 'query',
      name: 'amount',
      required: false,
      description: 'Absolute amount to use. Ignored when `share` is provided.',
      schema: { type: 'number', minimum: 0 },
    },
  },

  schemas: {
    ErrorResponse: {
      type: 'object',
      description:
        'Validation/rejection response. Fields are 1-element arrays for backwards ' +
        'compatibility with the original R/jsonlite wire format.',
      properties: {
        status: { type: 'array', items: { type: 'string' }, example: ['fail'] },
        status_code: { type: 'array', items: { type: 'string' }, example: ['1000'] },
        message: {
          type: 'array',
          items: { type: 'string' },
          example: ['Unrecognized network'],
        },
      },
    },
  },
} as const;

/** Standard error responses shared by validated endpoints. */
export const STANDARD_ERROR_RESPONSES = {
  '200': {
    description:
      'Success, or a validation failure. Failures return status="fail" with a ' +
      'status_code: 1000 unrecognized network, 1001 unrecognized protocol, ' +
      '1002 invalid API key, 1004 invalid pool address.',
  },
};
