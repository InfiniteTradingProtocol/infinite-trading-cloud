/**
 * shadow/endpoints/gasBalance.ts — Node port of R gateway's getGasBalance.R /
 * getAllGasBalance.R (proxies to plumber-api port 8002's
 * getGasBalanceHandler/getAllGasBalanceHandler in src/api/api.R, backed by
 * src/api/getGasBalances.R's live on-chain eth_getBalance RPC calls).
 *
 * PARITY NOTES (confirmed live via curl on EC2):
 *  - /getGasBalance: apiKey is a UUID validated via isValidAPIKey() (regex
 *    format check only, NOT a DB lookup) + wallet resolved via the ALREADY
 *    LIVE production Express endpoint GET /getWallet?apiKey=... (port 8000,
 *    src/requests/admin.ts) — proxied via HTTP exactly like R's getWallet()
 *    helper does (paste0(ep,"getWallet?apiKey=",apiKey)), rather than
 *    reimplementing DB/token decryption logic here.
 *  - /getAllGasBalance: uses manager+signature (EIP-191/EIP-1271) auth,
 *    verified via the ALREADY LIVE production Express endpoint
 *    POST /verifySignature (port 8000, src/requests/admin.ts) — proxied via
 *    HTTP exactly like R's verifySignature() helper does. This deliberately
 *    reuses the existing, security-critical, already-audited-in-production
 *    signature verification code rather than reimplementing EIP-1271 checks
 *    in a second place (avoids auth-bypass risk from subtle divergence).
 *  - Balance is fetched via live on-chain eth_getBalance RPC (ETH balance in
 *    native units), using the project's existing ethers RetryProvider +
 *    getAllRpcProviders() failover helper (same pattern used elsewhere in
 *    the codebase) rather than R's raw Alchemy JSON-RPC POST.
 *  - USD conversion price pair mapping (confirmed in R: src/api/api.R):
 *      polygon -> POL-USD, hyperliquid -> HYPE-USD, everything else -> ETH-USD
 *    Price is read via the ALREADY-PORTED /getTicks shadow endpoint's same
 *    Redis-backed lookup (see getTicks.ts) using apiKey="frontend" internally
 *    — matches R calling getTicks(exchange="coinbase", pair=pair) directly
 *    (no apiKey check inside that internal R call since it's a same-process
 *    function call, not an HTTP round-trip through the "frontend"-key gate).
 *  - /getAllGasBalance: response fields are `network`, `address`, `balance`
 *    (raw ETH balance), and `usd_balance` rounded to 2 decimal places (R:
 *    `round(entry$balance * price, 2)`) — confirmed from source, this DIFFERS
 *    from /getGasBalance's "all" case (which only returns `usd_balance`
 *    rounded to 6 decimals, no raw `balance` field). Treat these as two
 *    genuinely different response shapes, not variants of the same one.
 *  - "all" case network order is NOT deterministic/documented in R source
 *    (confirmed live: two consecutive requests both returned
 *    ethereum, arbitrum, optimism, polygon, base — an order that doesn't
 *    match either `networks` array literal found in the R codebase, meaning
 *    it's likely influenced by RPC response timing or another indirection
 *    not visible in the reviewed source). This port uses its own fixed
 *    iteration order (ethereum, polygon, optimism, arbitrum, base) rather
 *    than attempting to replicate an order that isn't actually guaranteed by
 *    the R implementation itself — callers should treat this list as
 *    unordered (matched by the `network` field), not positionally.
 */

import { Router, Request, Response } from 'express';
import { ethers } from 'ethers';
import { createRetryProviderWithFailover } from '../utils/RetryProvider';
import { getAllRpcProviders } from '../rpc';
import { Network } from '@dhedge/v2-sdk';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

function isValidAPIKeyFormat(apiKey: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(apiKey);
}

function isValidNetworkName(network: string): boolean {
  return ['ethereum', 'polygon', 'optimism', 'arbitrum', 'base'].includes(network);
}

const NETWORKS: Network[] = [Network.ETHEREUM, Network.POLYGON, Network.OPTIMISM, Network.ARBITRUM, Network.BASE];
const NETWORK_NAMES = ['ethereum', 'polygon', 'optimism', 'arbitrum', 'base'];

async function getWalletForApiKey(apiKey: string): Promise<string | null> {
  const resp = await fetch(`${EXPRESS_BASE}getWallet?apiKey=${encodeURIComponent(apiKey)}`);
  const data: any = await resp.json();
  if (data.status === 'success') return data.msg;
  return null;
}

async function getEthBalance(address: string, networkName: string): Promise<number> {
  const netEnum = NETWORKS[NETWORK_NAMES.indexOf(networkName)];
  const provider = createRetryProviderWithFailover(getAllRpcProviders(netEnum));
  const balanceWei = await provider.getBalance(address);
  return Number(ethers.utils.formatEther(balanceWei));
}

/** Same Redis-backed price lookup as getTicks.ts, called directly (no HTTP
 * round-trip / no "frontend" apiKey gate needed for this internal use). */
async function getTickPrice(pair: string): Promise<number> {
  const { getRedis } = await import('../lib/redis');
  const redis = await getRedis();
  const val = await redis.get(`coinbase_${pair}`);
  const price = val === null || val === undefined ? NaN : Number(val);
  return Number.isNaN(price) ? 0 : price;
}

function pairForNetwork(network: string): string {
  if (network === 'polygon') return 'POL-USD';
  if (network === 'hyperliquid') return 'HYPE-USD';
  return 'ETH-USD';
}

/**
 * @openapi
 * /getGasBalance:
 *   get:
 *     summary: Get the native gas token balance for the wallet linked to an API key
 *     tags: [Gas Wallets]
 *     parameters:
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid], description: "network name, or 'all'" }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: USD
 *         schema: { type: boolean, default: true }
 *     responses:
 *       200:
 *         description: Gas balance (optionally converted to USD).
 */
router.get('/getGasBalance', async (req: Request, res: Response) => {
  const network = String(req.query.network || '');
  const apiKey = String(req.query.apiKey || '');
  const usdRaw = req.query.USD;
  const USD = usdRaw === undefined ? true : String(usdRaw).toUpperCase() !== 'FALSE';

  if (network !== 'all' && !isValidNetworkName(network)) {
    return res.json({ status: ['fail'], status_code: ['1000'], message: ['Unrecognized network'] });
  }
  if (!isValidAPIKeyFormat(apiKey)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The API Key is invalid'] });
  }

  const wallet = await getWalletForApiKey(apiKey);
  if (!wallet) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The API Key is invalid'] });
  }

  try {
    if (network === 'all') {
      const result = [];
      for (const net of NETWORK_NAMES) {
        let balance = 0;
        try {
          balance = await getEthBalance(wallet, net);
        } catch (e) {
          balance = 0;
        }
        let price = 1;
        if (USD) {
          price = await getTickPrice(pairForNetwork(net));
        }
        result.push({
          network: [net],
          address: [wallet],
          usd_balance: [Math.round(balance * price * 1e6) / 1e6],
        });
      }
      return res.json({ status: ['success'], status_code: [200], message: result });
    }

    const balance = await getEthBalance(wallet, network);
    let price = 1;
    if (USD) {
      price = await getTickPrice(pairForNetwork(network));
    }
    return res.json({ status: ['success'], status_code: [200], message: [balance * price] });
  } catch (e: any) {
    console.log(`getGasBalance error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error'] });
  }
});

/**
 * @openapi
 * /getAllGasBalance:
 *   get:
 *     summary: Get gas token balances for all managed gas wallets (manager-signed, doc-hidden)
 *     tags: [Gas Wallets]
 *     parameters:
 *       - in: query
 *         name: network
 *         schema: { type: string, enum: [base, optimism, arbitrum, polygon, ethereum, mainnet, hyperliquid], default: all }
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: USD
 *         schema: { type: boolean, default: true }
 *     responses:
 *       200:
 *         description: Array of { network, address, balance, usd_balance }.
 */
router.get('/getAllGasBalance', async (req: Request, res: Response) => {
  const network = String(req.query.network || 'all');
  const manager = String(req.query.manager || '');
  const signature = String(req.query.signature || '');
  const usdRaw = req.query.USD;
  const USD = usdRaw === undefined ? true : String(usdRaw).toUpperCase() !== 'FALSE';

  if (!/^0x[0-9a-fA-F]{130,}$/.test(signature)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }

  try {
    const verifyResp = await fetch(`${EXPRESS_BASE}verifySignature`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: 'Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations.',
        signature,
        expectedAddress: manager,
        network,
      }),
    });
    const verifyData: any = await verifyResp.json();
    if (!(verifyResp.status === 200 && verifyData.status === 'success' && verifyData.isValid)) {
      return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
    }
  } catch (e) {
    return res.json({ status: ['fail'], status_code: [401], message: ['Invalid Signature'] });
  }

  if (network !== 'all' && !isValidNetworkName(network)) {
    return res.json({ status: ['fail'], status_code: ['1000'], message: ['Unrecognized network'] });
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(manager)) {
    return res.json({ status: ['fail'], status_code: [401], message: ['The manager address is invalid'] });
  }

  // getAssociatedGasWallets(manager, noKey=TRUE) equivalent — see getAssociatedGasWallets.ts
  // for the shared DB query; kept local here to avoid a circular import.
  const { dbQuery } = await import('../db');
  const rows = await dbQuery(
    'SELECT wallet_address AS wallet FROM gas_wallets WHERE manager = ? AND pool IS NULL',
    [manager.toLowerCase()]
  );
  if (rows.length === 0) {
    return res.json({ status: ['success'], status_code: [200], message: [] });
  }
  const addresses: string[] = rows.map((r) => r.wallet);

  try {
    const networksToQuery = network === 'all' ? NETWORK_NAMES : [network];
    const result: any[] = [];
    for (const net of networksToQuery) {
      let price = 1;
      if (USD) price = await getTickPrice(pairForNetwork(net));
      for (const addr of addresses) {
        let balance = 0;
        try {
          balance = await getEthBalance(addr, net);
        } catch (e) {
          balance = 0;
        }
        result.push({
          network: net,
          address: addr,
          balance,
          usd_balance: Math.round(balance * price * 100) / 100,
        });
      }
    }
    return res.json({ status: ['success'], status_code: [200], message: result });
  } catch (e: any) {
    console.log(`getAllGasBalance error: ${e.message}`);
    return res.json({ status: ['fail'], status_code: [500], message: ['Internal error'] });
  }
});

export default router;
