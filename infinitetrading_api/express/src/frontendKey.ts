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
 * There is deliberately NO fallback value. A missing FRONTEND_API_KEY is a
 * misconfigured deployment, and defaulting to the old literal would silently
 * re-enable a key we may have just rotated away from. Instead every frontend
 * request fails closed and startup logs a warning.
 */

export const FRONTEND_API_KEY_ENV = 'FRONTEND_API_KEY';

/**
 * Resolved lazily rather than at module load: dotenv is called from several
 * modules (rpc.ts, wallet.ts, txFees.ts...) with a relative path, so at import
 * time it may not have run yet. Reading it per-request avoids depending on
 * import order, and the cost is a property lookup.
 *
 * Returns undefined when unset, which makes isFrontendApiKey() reject
 * everything rather than fall back to a guessable default.
 */
export function getFrontendApiKey(): string | undefined {
  const v = process.env[FRONTEND_API_KEY_ENV];
  return v && v.length > 0 ? v : undefined;
}

/**
 * Called once at startup so a missing key surfaces in the logs immediately,
 * instead of as mysterious blank charts on the site.
 */
export function warnIfFrontendKeyMissing(): void {
  if (!getFrontendApiKey()) {
    console.warn(
      `[frontendKey] ${FRONTEND_API_KEY_ENV} is not set — every frontend-key ` +
      `endpoint (getCandles, getTicks, getAllYields, getTotalYield, ` +
      `getGasWalletPools, getAssociatedGasWallets) will reject all callers.`
    );
  }
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
  const expected = getFrontendApiKey();
  if (!expected) return false;
  const a = Buffer.from(candidate);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
