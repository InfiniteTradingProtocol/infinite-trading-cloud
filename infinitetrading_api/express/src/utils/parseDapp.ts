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
    // ODOS is sunset. Keep accepting the legacy alias and route it into the
    // supported fallback chain by starting from 1inch.
    "odos": Dapp.ONEINCH,
    "pendle": Dapp.PENDLE,
    "kyberswap": Dapp.KYBERSWAP,
    "hyperliquid": Dapp.HYPERLIQUID,
    "cowswap": Dapp.COWSWAP,
};

/** Human-readable list of valid platform values for error messages. */
export const VALID_PLATFORMS = Object.keys(DAPP_MAP)
    .filter(k => k !== "oneinch" && k !== "aave" && k !== "compound" && k !== "odos") // hide duplicates and deprecated alias
    .join(", ");

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
