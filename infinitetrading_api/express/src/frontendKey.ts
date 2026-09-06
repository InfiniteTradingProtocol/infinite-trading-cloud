/**
 * frontendKey.ts — the shared API key used by the public frontend.
 *
 * Several read-only endpoints (getCandles, getTicks, getAllYields,
 * getTotalYield, getGasWalletPools, getAssociatedGasWallets) authenticate with
 * a single shared token rather than a per-user UUID. It was historically the
 * hardcoded literal "frontend", duplicated across six files.
 *
 * It now comes from FRONTEND_API_KEY in express/.env so it can be rotated in
 * one place. Rotating it requires updating the frontend at the same time —
 * these endpoints reject any other value, so a mismatch makes the site's
 * charts and yield figures go blank.
 *
 * The default preserves the previous literal so that an environment without
 * the variable set keeps working exactly as before, rather than silently
 * failing every frontend request.
 */

export const FRONTEND_API_KEY_ENV = 'FRONTEND_API_KEY';

/** Previous hardcoded value; used when FRONTEND_API_KEY is unset. */
const LEGACY_DEFAULT = 'frontend';

/**
 * Resolved lazily rather than at module load: dotenv is called from several
 * modules (rpc.ts, wallet.ts, txFees.ts...) with a relative path, so at import
 * time it may not have run yet. Reading it per-request avoids depending on
 * import order, and the cost is a property lookup.
 */
export function getFrontendApiKey(): string {
  return process.env[FRONTEND_API_KEY_ENV] || LEGACY_DEFAULT;
}

/**
 * Constant-time comparison of a caller-supplied key against the frontend key.
 *
 * A plain `===` on a shared secret leaks its length and prefix through timing.
 * The exposure is small (this key gates read-only data) but the check is
 * cheap, and these endpoints are public and unauthenticated up to this point.
 */
export function isFrontendApiKey(candidate: unknown): boolean {
  if (typeof candidate !== 'string') return false;
  const a = Buffer.from(candidate);
  const b = Buffer.from(getFrontendApiKey());
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
