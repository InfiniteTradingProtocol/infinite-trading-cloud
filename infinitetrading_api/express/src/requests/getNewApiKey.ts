/**
 * requests/getNewApiKey.ts — Node port of the R gateway's getNewApiKey.R
 * (port 8003), which validated the private key then proxied to plumber-api
 * (port 8002) POST /getApiKey (api.R's getApiKeyHandler ~line 252), which
 * re-validated and called Express's own GET /getApiKey (admin.ts ~line 310)
 * -> walletv2.generateApiToken().
 *
 * ***HANDLES A PRIVATE KEY*** — the caller supplies an existing gas wallet's
 * private key and receives a fresh API token bound to it. The private key is
 * NEVER logged, never included in any error message, and never sent to
 * Telegram. Only the resulting (masked) API key and the derived wallet address
 * ever appear in logs.
 *
 * PARITY NOTES:
 *  1. isValidEthPrivateKey(privateKey) FIRST, before anything else — strips an
 *     optional 0x prefix, then requires exactly 64 hex characters. Fail ->
 *     {"status":["fail"],"status_code":[400],
 *      "message":["The provided private key is not valid to generate an API Key."]}
 *     (verified live against the R gateway, including the wire format and the
 *     original message's spelling).
 *  2. A missing privateKey param 500'd on the R gateway (plumber's missing-arg
 *     error). That is a crash, not a contract: this port treats a missing key
 *     as an invalid key and returns the same 400 payload as (1), which is
 *     strictly safer and cannot break a caller that was previously receiving a
 *     500 error page.
 *  3. Success -> {"status":["success"],"status_code":[200],"apiKey":["<uuid>"],
 *     "message":["The API for the provided private key has been succesfully
 *     generated."]} — R's typo in "succesfully" is preserved deliberately for
 *     wire compatibility.
 *  4. Failure of the token generation itself -> {status:"fail",
 *     status_code:400, message:"Failed to generate API key"} (the message the
 *     8002 layer produced when the Express call failed without a body message).
 *  5. Method: GET (the gateway registered GET /getNewApiKey).
 *  6. Rate limiting: the shared 600 req/min/IP bucket applied app-wide in
 *     index.ts, matching R gateway.R's rate_limit_middleware, which had no
 *     per-endpoint override for this path. No other restriction existed in R.
 *
 * WARNING (carried over from R's endpoint comment): a NEW API key is generated
 * on every invocation; this cannot be used to retrieve an existing API key for
 * an already-linked gas wallet.
 *
 * TRANSPORT (2026-09-06): a POST variant was added because a private key in a
 * GET query string is written verbatim to the nginx access log, browser
 * history and any intermediate proxy. POST with a JSON body keeps the secret
 * out of the request line. The GET form is retained for wire compatibility
 * with existing callers, and nginx now masks the privateKey query parameter so
 * the legacy path cannot leak either.
 */

import { Router, Request, Response } from 'express';
import { generateApiToken } from '../walletv2';
import { maskApiKey } from '../utils/telegram';

const router = Router();

/** Port of R's isValidEthPrivateKey() (api/helpers/apiHelpers.R ~line 90). */
function isValidEthPrivateKey(privateKey: unknown): boolean {
  if (typeof privateKey !== 'string') return false;
  const pk = privateKey.startsWith('0x') ? privateKey.slice(2) : privateKey;
  return pk.length === 64 && /^[0-9a-fA-F]+$/.test(pk);
}

/**
 * @openapi
 * /getNewApiKey:
 *   get:
 *     summary: Generate a new API key for an existing gas wallet private key
 *     description: >
 *       Used to import and link an existing gas wallet. Warning - a new API key
 *       is generated every time this endpoint is invoked, and it cannot be used
 *       to obtain the existing API key of an already-linked gas wallet.
 *     tags: [Wallet]
 *     parameters:
 *       - in: query
 *         name: privateKey
 *         required: true
 *         description: The gas wallet private key (64 hex characters, 0x prefix optional).
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Returns the newly generated API key.
 *       400:
 *         description: Bad request (invalid private key).
 *       500:
 *         description: Internal server error.
 */
async function handleGetNewApiKey(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };
  const privateKey = q.privateKey;

  if (!isValidEthPrivateKey(privateKey)) {
    return res.json({
      status: ['fail'],
      status_code: [400],
      message: ['The provided private key is not valid to generate an API Key.'],
    });
  }

  try {
    const apiKey = await generateApiToken(String(privateKey));
    console.log(`getNewApiKey: generated API key ${maskApiKey(apiKey)}`);
    return res.json({
      status: ['success'],
      status_code: [200],
      apiKey: [apiKey],
      message: ['The API for the provided private key has been succesfully generated.'],
    });
  } catch (e: any) {
    // e.message must never be echoed back: it can embed the input key.
    console.log('Error: getNewApiKey — token generation failed');
    return res.json({ status: ['fail'], status_code: [400], message: ['Failed to generate API key'] });
  }
}

router.get('/getNewApiKey', handleGetNewApiKey);
// Preferred transport: keeps the private key out of the URL, and therefore out
// of access logs, browser history and proxy logs.
router.post('/getNewApiKey', handleGetNewApiKey);

export default router;
