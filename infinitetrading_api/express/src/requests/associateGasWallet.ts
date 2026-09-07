/**
 * requests/associateGasWallet.ts — Node port of R gateway's
 * associateGasWallet.R (proxies to plumber-api port 8002's
 * associateGasWalletHandler in src/api/api.R).
 *
 * PARITY NOTES:
 *  - Gateway layer: label is truncated to 42 chars
 *    (`substr(label, 1, min(42, nchar(label)))`) before forwarding.
 *  - Inner (port 8002) layer, in this exact order:
 *      1. signature format + verifySignature(SIGNATURE_MESSAGE, signature,
 *         manager, network) -- fail -> 401 "Invalid Signature".
 *      2. wallet = getWallet(apiKey) (resolves the api-token -> its bound
 *         EOA address via Express's own /getWallet, already ported —
 *         reused directly here instead of re-implementing token->address
 *         resolution).
 *      3. isValidAPIKey(apiKey) format check (NOT the literal "frontend"
 *         check used by getAssociatedGasWallets — this is the UUID-shaped
 *         apiKey format validator) -- fail -> 401 "The API Key is invalid".
 *      4. isValidEthereumAddress(wallet) && isValidEthereumAddress(manager)
 *         -- fail -> 401 "Invalid Wallet or Manager".
 *      5. associateGasWallet(wallet, manager, label, apiKey) -- DB write:
 *         DELETE any existing manager+wallet association with pool IS NULL,
 *         then INSERT a fresh row (token, wallet_address, manager, label,
 *         network='', protocol='', is_active=1).
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { isValidAPIKey, isValidEthereumAddress } from '../basicCheck';
import { param } from '../utils/requestParam';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';
const SIGNATURE_MESSAGE =
  'Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations.';

async function verifySignatureViaExpress(signature: string, manager: string, network?: string): Promise<boolean> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}verifySignature`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: SIGNATURE_MESSAGE, signature, expectedAddress: manager, network }),
    });
    const data: any = await resp.json();
    return resp.status === 200 && data.status === 'success' && !!data.isValid;
  } catch {
    return false;
  }
}

async function getWalletForApiKey(apiKey: string): Promise<string | null> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}getWallet?apiKey=${encodeURIComponent(apiKey)}`);
    if (resp.status !== 200) return null;
    const data: any = await resp.json();
    return data && data.msg ? String(data.msg) : null;
  } catch {
    return null;
  }
}

// (isValidAPIKey / isValidEthereumAddress imported from ../basicCheck — same
// UUID-token format validator and 0x-address validator used elsewhere.)

/**
 * @openapi
 * /associateGasWallet:
 *   post:
 *     summary: Associate a gas wallet with a manager (doc-hidden)
 *     tags: [Gas Wallets]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: label
 *         schema: { type: string, default: main }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *     responses:
 *       200:
 *         description: Gas wallet associated.
 */
router.post('/associateGasWallet', async (req: Request, res: Response) => {
  // Accept parameters from either the query string or a JSON body. The route is
  // a POST and the frontend proxy sends a JSON body, but this handler only read
  // req.query -- so every frontend call failed with "Missing required
  // parameters" even though it had supplied them all. Reading both keeps the
  // existing query-string callers working.
  const apiKey = param(req, 'apiKey');
  const manager = param(req, 'manager');
  const signature = param(req, 'signature');
  const network = param(req, 'network');
  let label = param(req, 'label') ?? 'main';
  label = label.substring(0, 42);


  if (apiKey === undefined || manager === undefined || signature === undefined) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Missing required parameters: apiKey, manager, or signature'] });
  }

  if (!/^0x[0-9a-fA-F]{130,}$/.test(signature) || !(await verifySignatureViaExpress(signature, manager, network))) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }

  const wallet = await getWalletForApiKey(apiKey);

  if (!isValidAPIKey(apiKey)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The API Key is invalid'] });
  }

  if (!wallet || !isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Wallet or Manager'] });
  }

  try {
    const walletLower = wallet.toLowerCase();
    const managerLower = manager.toLowerCase();
    await dbQuery('DELETE FROM gas_wallets WHERE manager = ? AND wallet_address = ? AND pool IS NULL', [managerLower, walletLower]);
    await dbQuery(
      'INSERT INTO gas_wallets (token, wallet_address, manager, label, network, protocol, is_active) VALUES (?, ?, ?, ?, \'\', \'\', 1)',
      [apiKey, walletLower, managerLower, label]
    );
    return res.json({ status: ['success'], status_code: [200], message: ['Gas wallet successfully associated'] });
  } catch (e: any) {
    console.log(`Error: associateGasWallet — manager: ${manager} wallet: ${wallet} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error associating a gas wallet'] });
  }
});

export default router;
