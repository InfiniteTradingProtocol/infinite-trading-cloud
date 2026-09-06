/**
 * endpointVisibility.ts — single source of truth for which endpoints are
 * shown in the public Swagger/OpenAPI docs, mirroring (and correcting) the
 * R gateway's own `pr$setApiSpec()` hiding logic.
 *
 * IMPORTANT: R's `hidden_endpoints` array (src/api/helpers/endpoints.R) only
 * controls whether a path is deleted from R's OWN generated OpenAPI spec —
 * it is NOT access control. The real "is this reachable by anyone outside
 * the EC2 box" ground truth is nginx's `/etc/nginx/snippets/itp_endpoints.conf`,
 * which proxies a specific, curated list of paths to the R gateway (port 8003).
 * The main Express app (port 8000) has NO nginx server block of its own at
 * all — confirmed by grepping every nginx sites-enabled and snippets file on EC2 —
 * so anything only ever mounted there is EC2/internal-only by definition,
 * regardless of what R's swagger claims.
 *
 * These two facts do not agree with each other:
 *   - R's `endpoints` array lists `compoundV3` and `fluid` as mounted AND
 *     visible in R's own swagger (i.e. not in `hidden_endpoints`), but nginx
 *     never proxies either of them — they are NOT reachable from the public
 *     internet or the frontend today, despite what R's docs imply.
 *   - 14 endpoints (see PUBLIC_BUT_HIDDEN_ENDPOINTS below) ARE reachable
 *     through nginx today, but R deliberately hides them from its own
 *     swagger page.
 *
 * The Express docs page must match nginx's real behavior, not R's array.
 */

/**
 * Every endpoint nginx actually proxies to :8003 today, taken verbatim from
 * the live, active (non-commented) `include` line in
 * /etc/nginx/snippets/itp_endpoints.conf on EC2. This is the ONLY list that
 * determines "is this endpoint reachable from the internet/frontend at all."
 */
export const NGINX_PROXIED_ENDPOINTS = [
  'aaveV3', 'addLiquidity', 'approve', 'associateGasWallet', 'borrow',
  'createGasWallet', 'deactivateCEXBot', 'deassociateGasWallet', 'deleteBot',
  'deleteCEXBot', 'deleteCEXSubaccount', 'getAllBots', 'getAllCEXSubaccounts',
  'getAllGasBalance', 'getAllYields', 'getAssociatedGasWallets', 'getCEXSide',
  'getCandles', 'getContract', 'getEstimatedAnualYield', 'getGasBalance',
  'getGasWalletPools', 'getHealthFactor', 'getNewApiKey', 'getPoolAaveData',
  'getSymbol', 'getTicks', 'getTotalYield', 'lend', 'linkGasWallet',
  'llmIntrospect', 'mintManagerFee', 'poolComposition', 'registerCEXSubaccount',
  'removeLiquidity', 'repay', 'setBot', 'setCEXSide', 'setCEXStrategy',
  'unlend', 'unlinkGasWallet', 'vaultTrade',
] as const;

/**
 * Endpoints R mounts (`endpoints` array in endpoints.R) that nginx does NOT
 * proxy at all — genuinely EC2/internal-only, never reachable publicly,
 * regardless of R's own swagger visibility for them. Kept here only for
 * documentation/audit purposes; these must NEVER appear in Express's public
 * docs even if a shadow/production Express port of them exists someday.
 */
export const EC2_INTERNAL_ONLY_ENDPOINTS = ['compoundV3', 'fluid'] as const;

/**
 * Endpoints that ARE reachable through nginx today but that R deliberately
 * hides from its own generated swagger spec (`hidden_endpoints` in
 * endpoints.R). We replicate the same hiding in Express for parity — public
 * traffic can still call them, they're just not advertised in docs.
 */
export const PUBLIC_BUT_HIDDEN_ENDPOINTS = [
  'associateGasWallet', 'createGasWallet', 'deassociateGasWallet',
  'getAllBots', 'getAllCEXSubaccounts', 'getAllGasBalance', 'getAllYields',
  'getAssociatedGasWallets', 'getEstimatedAnualYield', 'getGasWalletPools',
  'getTotalYield', 'linkGasWallet', 'setCEXStrategy', 'unlinkGasWallet',
] as const;

const NGINX_SET = new Set<string>(NGINX_PROXIED_ENDPOINTS);
const HIDDEN_SET = new Set<string>(PUBLIC_BUT_HIDDEN_ENDPOINTS);

/** True if this base path (no leading slash) is reachable from the public internet via nginx today. */
export function isPubliclyReachable(endpointName: string): boolean {
  return NGINX_SET.has(endpointName);
}

/** True if this base path should be hidden from the public docs (but is still callable). */
export function isDocHidden(endpointName: string): boolean {
  return HIDDEN_SET.has(endpointName);
}

/**
 * Given a full OpenAPI `paths` object (keys are like "/getSymbol" or
 * "/aaveV3/lend"), returns a filtered copy containing ONLY paths that are:
 *   1. Actually proxied by nginx (i.e. genuinely public today), AND
 *   2. Not in R's hidden list (replicating R's cosmetic swagger hiding).
 *
 * Any path whose leading segment isn't in NGINX_PROXIED_ENDPOINTS is dropped
 * entirely — this is what prevents EC2-internal-only endpoints (like the
 * compoundV3/fluid mismatch above) from ever leaking into public docs just
 * because a route handler happens to exist for them somewhere in the code.
 */
export function filterPathsForPublicDocs(paths: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const path of Object.keys(paths)) {
    const firstSegment = path.split('/').filter(Boolean)[0];
    if (!firstSegment) continue;
    if (!isPubliclyReachable(firstSegment)) continue;
    if (isDocHidden(firstSegment)) continue;
    out[path] = paths[path];
  }
  return out;
}
