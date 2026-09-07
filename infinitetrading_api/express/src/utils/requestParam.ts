/**
 * Reads a request parameter from the query string, falling back to the JSON body.
 *
 * WHY THIS EXISTS
 * ---------------
 * Several POST/DELETE routes were written to read `req.query` only, but the
 * frontend proxies send their parameters as a JSON body. The result was that
 * every frontend call to those routes failed with "Missing required parameters"
 * while appearing to supply them all -- the endpoint simply looked in the wrong
 * place. Reading both sources fixes the frontend without breaking the existing
 * query-string callers (live strategies and scripts).
 *
 * Query wins over body so an explicit URL parameter is never silently
 * overridden by a stale body field.
 */
export function param(req: any, name: string): string | undefined {
  const fromQuery = (req.query as any)?.[name];
  if (fromQuery !== undefined) return String(fromQuery);
  const fromBody = (req.body as any)?.[name];
  return fromBody === undefined ? undefined : String(fromBody);
}
