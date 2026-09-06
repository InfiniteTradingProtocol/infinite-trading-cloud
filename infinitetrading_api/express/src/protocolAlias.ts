/**
 * protocolAlias.ts — normalizes protocol aliases before any route handler runs.
 *
 * dHEDGE rebranded to Chamber. Callers should be able to send
 * `protocol=chamber`, but everything downstream — the `protocols` table, the
 * dHEDGE SDK, `dhedge_sides`, and every stored row — still says `dhedge`.
 *
 * Rewriting the value once, in middleware, means:
 *   - every endpoint accepts `chamber` automatically, including any added later
 *   - no handler, query or SDK call has to know the alias exists
 *   - `dhedge` keeps working unchanged, so live strategies are unaffected
 *
 * This mirrors how the deprecated `odos` platform is folded into `auto`
 * (see utils/parseDapp.ts): accept the caller's term, act on the canonical one.
 */

import { Request, Response, NextFunction } from 'express';

/** Alias -> canonical protocol name stored in the database. */
export const PROTOCOL_ALIASES: Record<string, string> = {
  chamber: 'dhedge',
};

/** Resolves a protocol alias to its canonical name. Case-insensitive. */
export function normalizeProtocol(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  const canonical = PROTOCOL_ALIASES[value.trim().toLowerCase()];
  return canonical ?? value;
}

/**
 * Rewrites `protocol` in both the query string and the parsed body.
 *
 * Must be mounted AFTER the body parsers and BEFORE any router.
 */
export function protocolAliasMiddleware(req: Request, _res: Response, next: NextFunction): void {
  const q = req.query as Record<string, unknown> | undefined;
  if (q && q.protocol !== undefined) {
    q.protocol = normalizeProtocol(q.protocol);
  }

  const b = req.body as Record<string, unknown> | undefined;
  if (b && typeof b === 'object' && b.protocol !== undefined) {
    b.protocol = normalizeProtocol(b.protocol);
  }

  next();
}
