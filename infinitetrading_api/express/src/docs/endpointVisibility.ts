/**
 * endpointVisibility.ts — single source of truth for which endpoints appear
 * in the public Swagger/OpenAPI docs.
 *
 * Two independent questions, deliberately kept separate:
 *
 *   1. "Is this endpoint reachable from the internet at all?"
 *      Answered by nginx's allowlist, which is generated from the `endpoints`
 *      array in infinitetrading/src/api/helpers/endpoints.R. Anything not in
 *      that array has no nginx route and is EC2-internal-only, no matter what
 *      handlers exist in the code.
 *
 *   2. "Should it be advertised in the docs page?"
 *      Answered by the `hidden_endpoints` array in the same file. This is
 *      cosmetic only — hidden endpoints are still fully public and callable.
 *      NEVER treat this list as access control.
 *
 * Both lists are PARSED FROM endpoints.R AT STARTUP rather than duplicated
 * here. A previous version hardcoded them, and it silently drifted: endpoints
 * were added to nginx but not to the copy in this file, so the docs page
 * disagreed with reality. Parsing the same file nginx's generator reads makes
 * that class of drift impossible.
 */

import fs from 'fs';
import path from 'path';

/** Candidate locations for endpoints.R, in priority order (EC2 first, then repo layouts). */
const ENDPOINTS_R_CANDIDATES = [
  process.env.ENDPOINTS_R_PATH,
  '/home/ubuntu/infinitetrading/src/api/helpers/endpoints.R',
  path.join(__dirname, '../../../../infinitetrading/src/api/helpers/endpoints.R'),
].filter((p): p is string => typeof p === 'string' && p.length > 0);

function readEndpointsR(): string | null {
  for (const candidate of ENDPOINTS_R_CANDIDATES) {
    try {
      if (fs.existsSync(candidate)) return fs.readFileSync(candidate, 'utf8');
    } catch {
      /* try the next candidate */
    }
  }
  return null;
}

/**
 * Extracts the string literals from an R vector assignment such as
 *   endpoints <- c("a", "b", ...)
 * Tolerates newlines, comments and inconsistent spacing.
 */
function parseRCharacterVector(source: string, variableName: string): string[] {
  const start = new RegExp(`${variableName}\\s*(?:<-|=)\\s*c\\(`).exec(source);
  if (!start) return [];

  const open = start.index + start[0].length - 1;
  let depth = 0;
  let end = -1;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '(') depth++;
    else if (source[i] === ')') {
      depth--;
      if (depth === 0) { end = i; break; }
    }
  }
  if (end === -1) return [];

  const body = source.slice(open + 1, end);
  return Array.from(body.matchAll(/"([^"]+)"/g))
    .map((m) => m[1].replace(/^\//, '').trim())
    .filter(Boolean);
}

const source = readEndpointsR();

if (!source) {
  // Fail loudly rather than silently publishing an empty or wrong docs page.
  console.warn(
    '[docs] Could not locate endpoints.R; the public API docs page will be ' +
      'EMPTY. Set ENDPOINTS_R_PATH to fix. Endpoint routing itself is ' +
      'unaffected — this only impacts the docs page.',
  );
}

/**
 * Every endpoint nginx proxies publicly — parsed from the `endpoints` array
 * that nginx's own generator (gateway/deploy.sh) reads.
 */
export const PUBLIC_ENDPOINTS: readonly string[] = source
  ? parseRCharacterVector(source, 'endpoints')
  : [];

/**
 * Endpoints that are public and callable but deliberately not advertised in
 * the docs page. Cosmetic only — not access control.
 */
export const DOC_HIDDEN_ENDPOINTS: readonly string[] = source
  ? parseRCharacterVector(source, 'hidden_endpoints')
  : [];

const PUBLIC_SET = new Set<string>(PUBLIC_ENDPOINTS);
const HIDDEN_SET = new Set<string>(DOC_HIDDEN_ENDPOINTS);

/** True if this base path is routable from the public internet. */
export function isPubliclyReachable(endpointName: string): boolean {
  return PUBLIC_SET.has(endpointName);
}

/** True if this base path is public but omitted from the docs page. */
export function isDocHidden(endpointName: string): boolean {
  return HIDDEN_SET.has(endpointName);
}

/**
 * Filters an OpenAPI `paths` object down to what should be documented.
 *
 * Keys look like "/getSymbol" or "/aaveV3/lend"; visibility is decided by the
 * FIRST path segment, because that is the granularity at which nginx routes.
 *
 * Dropping anything whose leading segment isn't public is what prevents
 * internal-only routes from leaking into the docs merely because a handler
 * exists for them somewhere in the codebase.
 */
export function filterPathsForPublicDocs(
  paths: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const p of Object.keys(paths)) {
    const firstSegment = p.split('/').filter(Boolean)[0];
    if (!firstSegment) continue;
    if (!isPubliclyReachable(firstSegment)) continue;
    if (isDocHidden(firstSegment)) continue;
    out[p] = paths[p];
  }
  return out;
}
