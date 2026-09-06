/**
 * requests/yields.ts — PROMOTED from shadow/endpoints/yields.ts to production
 * (Bucket A cutover, 2026-09-06). Reads straight from Redis, no dependency on
 * R's port-8002 inner API. Parity-verified (29/29) before promotion.
 *
 * Node port of R's getTotalYield / getEstimatedAnualYield
 * / getAllYields gateway endpoints (src/api/gateway/endpoints/getTotalYield.R,
 * getEstimatedAnualYield.R, getAllYields.R -> proxied via `pep` (port 8002) to
 * src/api/api.R's getTotalYield()/getEstimatedAnualYield()/getAllYields(), which
 * read straight from Redis).
 *
 * PARITY NOTES (confirmed live against R gateway on 2026-09-05):
 *  - Auth is NOT the UUID apiKey scheme used elsewhere. It's a literal string
 *    check: `apiKey == "frontend"`. Any other value -> {status:"fail",
 *    status_code:[401], message:["Invalid API Key"]}. This is a different,
 *    weaker auth model than basic_check() — intentional in the original code
 *    (internal use for the frontend only, per the R comment), not something to
 *    "fix" here — just replicate.
 *  - Pool address format is validated (regex, case-insensitive, lowercased
 *    before lookup) BEFORE the apiKey check for getTotalYield/getEstimatedAnualYield
 *    (confirmed: an invalid pool format returns "Invalid pool address" even
 *    with a bad apiKey — meaning pool-format-validation runs first in the R
 *    handler, since `isValidEthereumAddress(pool)` check appears above the
 *    apiKey check inside getTotalYieldHandler/getEstimatedAnualYieldHandler).
 *  - Redis keys: `${pool}_totalYield` and `${pool}_APY` (raw string values,
 *    written by other bots/monitors — this port only READS, never writes).
 *  - Response shapes (confirmed live):
 *      getTotalYield          -> a bare JSON array with one number: [0.0377...]
 *      getEstimatedAnualYield -> a bare JSON array with one number: [0.0118...]
 *      getAllYields           -> { [poolAddress]: { totalYield: [n], APY: [n] }, ... }
 *    All numeric leaves are wrapped in 1-element arrays (R's jsonlite scalar
 *    auto-unbox=FALSE behavior, same quirk as basic_check() responses — see
 *    src/shadow/basicCheck.ts's toRWireFormat() for background).
 *  - If a Redis key doesn't exist (unknown pool), R's `r$GET()` returns NULL,
 *    and getTotalYield()/getEstimatedAnualYield() return
 *    {status:"fail", message:"Invalid pool"} (NOT wrapped in arrays, since this
 *    branch doesn't wrap fields — see raw R source, no status_code either).
 *  - getAllYields() iterates a HARDCODED pool list (`pools` in
 *    src/api/helpers/yieldPools.R) — replicated as POOL_LIST below. Keep this
 *    in sync manually if that list changes; there's no dynamic discovery.
 */

import { Router, Request, Response } from 'express';
import { getRedis } from '../lib/redis';

const router = Router();

const FRONTEND_API_KEY = 'frontend';

// Mirrors src/api/helpers/yieldPools.R's `pools` vector exactly (order matters
// for getAllYields, though callers should treat the result as a map by key).
const POOL_LIST = [
  '0xb1569ec05aba57fd9256ba3816ae9221f23306ee',
  '0xc3ffa8d537e31ebf83e7f5f43b481c8101545352',
  '0x08837d4bc031b9f7641e25cc901d91424081a176',
  '0x423582afb8e8693a427bf67d76adf9f6a8e33124',
  '0xd770898671f6d73c6206a4517d7c92d392ce4b9f',
  '0xa2ffe6ed599e8f7aac8047f5ee0de3d83de1b320',
  '0x948720ff3f5f26f889b42e22ee8d1c23da5063a3',
  '0x37acdfc02b78b53c9a0e21a58746cc71e23a8f05',
  '0xe51af0ba747b9c464057b9099040f4df0b29a7de',
  '0x54db076bfac96c02e9a2a66410d69f35ac481fe6',
];

function isValidEthereumAddress(address: string): boolean {
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

function invalidApiKeyResponse() {
  return { status: ['fail'], status_code: [401], message: ['Invalid API Key'] };
}

/**
 * jsonlite's default toJSON(digits=4) rounds numeric scalars to 4 DECIMAL
 * places (not significant digits) when serializing a bare/top-level atomic
 * value — confirmed live on the box via
 *   Rscript -e 'jsonlite::toJSON(0.0373650558081223)' -> [0.0374]
 *   Rscript -e 'round(0.0373650558081223, 4)'          -> 0.0374
 * This must be replicated for getTotalYield/getEstimatedAnualYield's
 * single-value response, but NOT for getAllYields, where values are
 * serialized as raw strings inside a nested list (jsonlite doesn't apply
 * the same rounding there — confirmed live the nested values keep full
 * string precision, e.g. "4.8879144252334e-05").
 */
function toSignificantDigits(n: number, digits = 4): number {
  if (n === 0) return 0;
  const factor = 10 ** digits;
  return Math.round(n * factor) / factor;
}

/** Reads a redis string value as-is (no parsing) — used by getAllYields, which
 * mirrors R's behavior of keeping values as raw strings. */
async function readRedisRaw(key: string): Promise<string | null> {
  const redis = await getRedis();
  const val = await redis.get(key);
  return val === undefined ? null : val;
}

/** Reads a redis string value and returns it parsed as a float, or null if missing. */
async function readRedisFloat(key: string): Promise<number | null> {
  const redis = await getRedis();
  const val = await redis.get(key);
  if (val === null || val === undefined) return null;
  const num = Number(val);
  return Number.isNaN(num) ? null : num;
}

/**
 * @openapi
 * /getTotalYield:
 *   get:
 *     summary: Get the total historical yield for a pool (doc-hidden, matching R's hidden_endpoints)
 *     tags: [Yields]
 *     parameters:
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Single-element array with the total yield value.
 */
router.get('/getTotalYield', async (req: Request, res: Response) => {
  const poolRaw = String(req.query.pool || '');
  const apiKey = String(req.query.apiKey || '');
  const pool = poolRaw.toLowerCase();

  if (!isValidEthereumAddress(pool)) {
    return res.json({ status: ['fail'], message: ['Invalid pool address'] });
  }
  if (apiKey !== FRONTEND_API_KEY) {
    return res.json(invalidApiKeyResponse());
  }

  const totalYield = await readRedisFloat(`${pool}_totalYield`);
  if (totalYield === null) {
    return res.json({ status: 'fail', message: 'Invalid pool' });
  }
  return res.json([toSignificantDigits(totalYield)]);
});

/**
 * @openapi
 * /getEstimatedAnualYield:
 *   get:
 *     summary: Get the estimated annual yield (APY) for a pool (doc-hidden, matching R's hidden_endpoints)
 *     tags: [Yields]
 *     parameters:
 *       - in: query
 *         name: pool
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Single-element array with the APY value.
 */
router.get('/getEstimatedAnualYield', async (req: Request, res: Response) => {
  const poolRaw = String(req.query.pool || '');
  const apiKey = String(req.query.apiKey || '');
  const pool = poolRaw.toLowerCase();

  if (!isValidEthereumAddress(pool)) {
    return res.json({ status: ['fail'], message: ['Invalid pool address'] });
  }
  if (apiKey !== FRONTEND_API_KEY) {
    return res.json(invalidApiKeyResponse());
  }

  const apy = await readRedisFloat(`${pool}_APY`);
  if (apy === null) {
    return res.json({ status: 'fail', message: 'Invalid pool' });
  }
  return res.json([toSignificantDigits(apy)]);
});

/**
 * @openapi
 * /getAllYields:
 *   get:
 *     summary: Get total yield and APY for every known pool (doc-hidden, matching R's hidden_endpoints)
 *     tags: [Yields]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Map of pool address to { totalYield, APY }.
 */
router.get('/getAllYields', async (req: Request, res: Response) => {
  const apiKey = String(req.query.apiKey || '');
  if (apiKey !== FRONTEND_API_KEY) {
    return res.json(invalidApiKeyResponse());
  }

  const result: Record<string, { totalYield: [string | null]; APY: [string | null] }> = {};
  for (const pool of POOL_LIST) {
    const [totalYield, apy] = await Promise.all([
      readRedisRaw(`${pool}_totalYield`),
      readRedisRaw(`${pool}_APY`),
    ]);
    result[pool] = { totalYield: [totalYield], APY: [apy] };
  }
  return res.json(result);
});

export default router;
