import { Dapp } from "@dhedge/v2-sdk";

/**
 * All valid SDK Dapp values, keyed by their lowercase alias(es).
 * Accepts any case from callers (e.g. "VelodromeCL", "velodromecl", "VELODROMECL").
 */
const DAPP_MAP: Record<string, Dapp> = {
    "sushiswap": Dapp.SUSHISWAP,
    "aave": Dapp.AAVEV3,      // "aave" is treated as aavev3 (current version)
    "aavev3": Dapp.AAVEV3,
    "oneinch": Dapp.ONEINCH,
    "1inch": Dapp.ONEINCH,
    "quickswap": Dapp.QUICKSWAP,
    "balancer": Dapp.BALANCER,
    "uniswapv3": Dapp.UNISWAPV3,
    "arrakis": Dapp.ARRAKIS,
    "toros": Dapp.TOROS,
    "velodrome": Dapp.VELODROME,
    "velodromev2": Dapp.VELODROMEV2,
    "velodromecl": Dapp.VELODROMECL,
    "lyra": Dapp.LYRA,
    "aerodrome": Dapp.AERODROME,
    "aerodromecl": Dapp.AERODROMECL,
    "pancakecl": Dapp.PANCAKECL,
    "compoundv3": Dapp.COMPOUNDV3,
    "compound": Dapp.COMPOUNDV3,  // alias
    // ── Automatic DEX routing ────────────────────────────────────────────────
    // "auto" is the DEFAULT and preferred routing mode: the trade executor
    // (trade-fallback.ts) walks the per-network fallback chain, which always
    // starts at 1inch and then tries kyberswap/uniswapV3/quickswap, skipping
    // any DEX that is currently banned or not whitelisted by the vault guard.
    // Resolving "auto" to ONEINCH therefore enters the chain at its head,
    // which is exactly what "let the bot pick the DEX" means in practice.
    "auto": Dapp.ONEINCH,
    // ODOS is DEPRECATED/sunset. We still ACCEPT the legacy alias so that live
    // strategies passing platform=odos do not break, but it is never actually
    // used: it resolves to the same automatic routing as "auto".
    "odos": Dapp.ONEINCH,
    "pendle": Dapp.PENDLE,
    "kyberswap": Dapp.KYBERSWAP,
    "hyperliquid": Dapp.HYPERLIQUID,
    "cowswap": Dapp.COWSWAP,
};

/** Aliases hidden from the human-readable platform list (duplicates + deprecated). */
const HIDDEN_ALIASES = new Set(["oneinch", "aave", "compound", "odos"]);

/** Human-readable list of valid platform values for error messages. */
export const VALID_PLATFORMS = Object.keys(DAPP_MAP)
    .filter(k => !HIDDEN_ALIASES.has(k))
    .join(", ");

/**
 * The default platform used when a caller omits `platform`. Automatic routing
 * lets the executor choose the best available DEX per network.
 */
export const DEFAULT_PLATFORM = "auto";

/**
 * Parse a platform string (from a query param or request body) into the
 * corresponding SDK `Dapp` enum value.
 *
 * @param platform - Raw platform string from caller (any casing)
 * @throws Error with a descriptive message listing valid options if unknown
 */
export function parseDapp(platform: string): Dapp {
    const key = platform.toLowerCase();
    const resolved = DAPP_MAP[key];
    if (!resolved) {
        throw new Error(
            `Unknown platform "${platform}". Valid options: ${VALID_PLATFORMS}`
        );
    }
    return resolved;
}
