/**
 * requests/deassociateGasWallet.ts — Node port of R gateway's
 * deassociateGasWallet.R (proxies to plumber-api port 8002's
 * deassociateGasWalletHandler in src/api/api.R).
 *
 * PARITY NOTES:
 *  - Inner (port 8002) layer, in this order:
 *      1. signature format + verifySignature(SIGNATURE_MESSAGE, signature,
 *         manager, network) -- fail -> 401 "Invalid Signature".
 *      2. isValidEthereumAddress(wallet) && isValidEthereumAddress(manager)
 *         -- fail -> 401 "Invalid Wallet or Manager".
 *      3. deassociateGasWallet(wallet, manager) -- DB write:
 *         DELETE FROM gas_wallets WHERE wallet_address = ? AND manager = ?
 *         AND pool IS NULL.
 *  - No apiKey format/DB check on this endpoint in R (unlike
 *    associateGasWallet) -- confirmed from source, apiKey is accepted as a
 *    parameter but never validated by deassociateGasWalletHandler.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { isValidEthereumAddress } from '../basicCheck';

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

/**
 * @openapi
 * /deassociateGasWallet:
 *   delete:
 *     summary: Deassociate a gas wallet from a manager (doc-hidden)
 *     tags: [Gas Wallets]
 *     parameters:
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: wallet
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid] }
 *     responses:
 *       200:
 *         description: Gas wallet deassociated.
 */
router.delete('/deassociateGasWallet', async (req: Request, res: Response) => {
  const apiKey = req.query.apiKey === undefined ? undefined : String(req.query.apiKey);
  const wallet = req.query.wallet === undefined ? undefined : String(req.query.wallet);
  const manager = req.query.manager === undefined ? undefined : String(req.query.manager);
  const signature = req.query.signature === undefined ? undefined : String(req.query.signature);
  const network = req.query.network === undefined ? undefined : String(req.query.network);

  if (apiKey === undefined || wallet === undefined || manager === undefined || signature === undefined) {
    return res.json({ status: ['fail'], status_code: [400], message: ['Missing required parameters: apiKey, wallet, manager, or signature'] });
  }

  if (!/^0x[0-9a-fA-F]{130,}$/.test(signature) || !(await verifySignatureViaExpress(signature, manager, network))) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }

  if (!isValidEthereumAddress(wallet) || !isValidEthereumAddress(manager)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Wallet or Manager'] });
  }

  try {
    const walletLower = wallet.toLowerCase();
    const managerLower = manager.toLowerCase();
    await dbQuery('DELETE FROM gas_wallets WHERE wallet_address = ? AND manager = ? AND pool IS NULL', [walletLower, managerLower]);
    return res.json({ status: ['success'], status_code: [200], message: ['Gas wallet successfully deassociated'] });
  } catch (e: any) {
    console.log(`Error: deassociateGasWallet — wallet: ${wallet} manager: ${manager} error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error deassociating gas wallet'] });
  }
});

export default router;
