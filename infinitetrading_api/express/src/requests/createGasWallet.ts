/**
 * requests/createGasWallet.ts — Node port of the R gateway's createGasWallet.R
 * (port 8003), which proxied to plumber-api (port 8002) POST /createWallet
 * (api.R's createWalletHandler ~line 146), which in turn called Express's own
 * POST /createWallet and GET /getApiKey.
 *
 * ***HANDLES A PRIVATE KEY*** — creates a brand-new Ethereum keypair and
 * returns it once, so the caller can fund it as a gas wallet. The key is
 * generated fresh here and belongs to nobody until it is returned, but it is
 * still secret material: it is NEVER logged, never sent to Telegram, and never
 * echoed anywhere but the HTTP response body.
 *
 * PARITY NOTES:
 *  - The R gateway performs NO validation at all (the handler takes no
 *    parameters) and no auth. Replicated exactly — tightening this would break
 *    the onboarding flow that depends on it being callable anonymously.
 *  - Rate limiting is the shared 600 req/min/IP bucket applied app-wide in
 *    index.ts (matching R gateway.R's rate_limit_middleware, which likewise had
 *    no per-endpoint override for this path) plus nginx's limit_req zone.
 *  - Method: GET (the gateway registered GET /createGasWallet).
 *  - Response shape (verified live against the R gateway, jsonlite array wire
 *    format): {"status":["success"],"status_code":[200],"address":["0x.."],
 *    "private_key":["<64 hex, NO 0x prefix>"],"apiKey":["<uuid>"]}.
 *    The 0x prefix stripping comes from R's createWalletHandler
 *    (remove_0x_prefix) and the privateKey -> private_key rename from the
 *    gateway layer; both are replicated so existing clients keep working.
 *  - On failure the 8002 layer returned
 *    {status:"fail", status_code:500, message:"Failed to create wallet"} /
 *    "Failed to generate API token" — replicated.
 *
 * SWAGGER: /createGasWallet is in R's `hidden_endpoints`
 * (infinitetrading/src/api/helpers/endpoints.R) so it must NOT appear in the
 * public docs. That hiding is enforced centrally by
 * shadow/docs/endpointVisibility.ts (PUBLIC_BUT_HIDDEN_ENDPOINTS already lists
 * 'createGasWallet'), which strips the path from the generated spec. No
 * @openapi annotation is added here, so it is doubly hidden.
 */

import { Router, Request, Response } from 'express';
import { ethers } from 'ethers';
import { generateApiToken } from '../walletv2';

const router = Router();

/** Port of R's remove_0x_prefix(). */
function remove0x(pk: string): string {
  return pk.startsWith('0x') || pk.startsWith('0X') ? pk.slice(2) : pk;
}

// Intentionally NOT annotated with @openapi — hidden endpoint (see header).
router.get('/createGasWallet', async (_req: Request, res: Response) => {
  let wallet: ethers.Wallet;
  try {
    wallet = ethers.Wallet.createRandom();
  } catch (e: any) {
    console.log(`Error: createGasWallet — wallet generation failed: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: 'Failed to create wallet' });
  }

  let apiKey: string;
  try {
    apiKey = await generateApiToken(wallet.privateKey);
  } catch (e: any) {
    // Never include the private key (or any part of it) in the log line.
    console.log(`Error: createGasWallet — API token generation failed: ${e.message}`);
    return res.json({ status: 'fail', status_code: 500, message: 'Failed to generate API token' });
  }

  console.log(`New Gas Wallet Successfully Created — address: ${wallet.address}`);

  // No Telegram notification here, matching R: the gateway/8002 handlers for
  // this endpoint never called send_telegram_text, and the payload contains
  // secret material that must not be forwarded to a chat channel.
  return res.json({
    status: ['success'],
    status_code: [200],
    address: [wallet.address],
    private_key: [remove0x(wallet.privateKey)],
    apiKey: [apiKey],
  });
});

export default router;
