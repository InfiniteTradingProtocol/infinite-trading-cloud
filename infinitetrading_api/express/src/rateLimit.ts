/**
 * rateLimit.ts — replicates the R gateway's in-process rate limiter
 * (infinitetrading/src/api/gateway/gateway.R's `rate_limit_middleware`)
 * for the Express side, using the `express-rate-limit` package.
 *
 * R's behavior (source of truth):
 *   - Keyed by client IP (req$HTTP_X_REAL_IP).
 *   - Default: 600 requests / 60s sliding window, per IP, across ALL endpoints
 *     combined (not per-endpoint) — R's `endpoint_key <- client_ip` for every
 *     endpoint except llmIntrospect.
 *   - llmIntrospect: a SEPARATE, stricter counter — 10 requests / 60s per IP,
 *     tracked independently from the shared 600/min bucket
 *     (`endpoint_key <- paste0(client_ip, "_llmIntrospect")`).
 *   - On exceed: HTTP 429 with `{error: "Rate limit exceeded"}` (or a more
 *     detailed message + retry_after for llmIntrospect).
 *
 * This is applied at the Express app level as defense-in-depth alongside the
 * nginx-level `limit_req_zone` (see itp_endpoints.conf generator) so rate
 * limiting still holds even if nginx is ever bypassed or misconfigured, and
 * so the llmIntrospect-specific stricter limit (which nginx's single global
 * zone doesn't distinguish) is enforced correctly.
 */

import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { Request } from 'express';

// Trust nginx's X-Real-IP / X-Forwarded-For (app.set('trust proxy', ...) must
// be configured by the app before this middleware is used).
//
// IPv6 note: a single IPv6 customer is typically allocated a whole /64, so
// keying on the raw address would let a client rotate through addresses it
// already owns and bypass the limit entirely. `ipKeyGenerator` normalizes
// IPv6 down to its /64 prefix (and leaves IPv4 untouched), which is what
// makes the limit actually enforceable. R keyed on the raw IP and had this
// same weakness; this is a deliberate improvement, not a parity break.
function keyByRealIp(req: Request): string {
  const xRealIp = req.headers['x-real-ip'];
  const ip = typeof xRealIp === 'string' && xRealIp.length > 0 ? xRealIp : req.ip;
  if (!ip) return 'unknown';
  return ipKeyGenerator(ip);
}

/** Default limiter: 600 req / 60s per IP, matches R's shared bucket. */
export const defaultRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 600,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: keyByRealIp,
  message: { error: 'Rate limit exceeded' },
});

/** llmIntrospect limiter: 10 req / 60s per IP, matches R's stricter bucket. */
export const llmIntrospectRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: keyByRealIp,
  message: {
    error: 'Rate limit exceeded',
    message: 'llmIntrospect endpoint limited to 10 requests per minute to prevent abuse',
    retry_after: 60,
  },
});
