/**
 * requests/aaveV3.ts — Node port of R gateway's aaveV3 sub-router
 * (src/api/gateway/endpoints/aaveV3.R), mounted at /aaveV3/* in the R
 * gateway (port 8003). Historically: /aaveV3/lend -> basic_check() -> port
 * 8002's /lend -> Express's own /lend (now /lendRaw); /aaveV3/unlend ->
 * port 8002's /unlend; /aaveV3/borrow -> port 8002's /borrow; /aaveV3/repay
 * -> port 8002's /repay; /aaveV3/getPoolData & /aaveV3/getHealthFactor ->
 * port 8002's /getPoolAaveData & /getHealthFactor; /aaveV3/getBorrowed &
 * /aaveV3/getSupplied -> Express's own /getBorrowed & /getSupplied directly
 * (port 8002 in R terms == Express port 8000 in our world, since port-8002
 * handlers themselves only add an api_check+asset-resolution layer in front
 * of the SAME Express endpoints this router now calls directly).
 *
 * IMPORTANT PARITY NOTE — WEAKER AUTH THAN /lend,/unlend,/borrow,/repay:
 * R's aaveV3 sub-router validates with basic_check() ONLY (network, protocol
 * format, apiKey format, pool address format) — it does NOT call
 * isValidTrader()/api_check(). This means /aaveV3/lend etc. do NOT verify
 * that the API key's wallet is actually a registered trader on the pool,
 * unlike the top-level /lend endpoint (requests/lend.ts) which DOES check
 * this. This is R's existing (arguably weaker) production behavior for the
 * aaveV3/compoundV3/fluid sub-routers and is replicated faithfully here —
 * see requests/lend.ts's much stricter validation chain for comparison.
 *
 * Since R's aaveV3$lend/unlend/borrow/repay ultimately hit the exact same
 * Express endpoints as the top-level handlers (just with get_contract()
 * asset resolution done identically), we delegate to the SAME *Raw
 * endpoints used by requests/lend.ts etc., just with basicCheck-only gating.
 *
 * asset here is passed through AS-IS to Express (R's aaveV3.R does NOT call
 * get_contract() — it forwards `asset` directly, unlike lendHandler). This
 * means callers of /aaveV3/lend must already pass a contract address (or a
 * symbol that Express's own /lendRaw can resolve, which it cannot — so in
 * practice R's aaveV3.R requires callers to pass a 0x address for `asset`).
 * Replicated faithfully: no symbol resolution performed here either.
 */

import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';
import { dbQuery } from '../db';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

// Port of R's get_contract(coin, network): pass through if already a 0x
// address, otherwise resolve via the coins/networks DB tables. Used here by
// getBorrowed/getSupplied to mirror port-8002's getBorrowedHandler/
// getSuppliedHandler, which both resolve `asset` this way before forwarding.
async function getContract(coin: string, network: string): Promise<string | null> {
  if (isValidEthereumAddress(coin)) return coin;
  try {
    const rows = await dbQuery(
      'SELECT c.contract FROM coins c JOIN networks n ON c.network_id = n.network_id WHERE c.symbol = ? AND n.name = ?',
      [coin.toLowerCase(), network.toLowerCase()]
    );
    return rows.length > 0 ? String(rows[0].contract) : null;
  } catch {
    return null;
  }
}

async function proxyPost(url: string): Promise<any> {
  const resp = await fetch(url, { method: 'POST' });
  const data: any = await resp.json().catch(() => ({}));
  if (resp.status === 200) return data;
  return { status: 'fail', status_code: resp.status, message: data };
}

async function proxyGet(url: string): Promise<any> {
  const resp = await fetch(url, { method: 'GET' });
  const data: any = await resp.json().catch(() => ({}));
  if (resp.status === 200) return data;
  return { status: 'fail', status_code: resp.status, message: data };
}

// share/amount handling mirrors R's aaveV3.R exactly: share default 100,
// amount default 0; share (if in (0,100]) takes precedence and is appended,
// amount is appended only if > 0, and if share missing/invalid AND amount
// missing/<=0 -> fail 1009.
function buildShareAmountParams(q: any): { params: string; error?: { status: string; status_code: number; message: string } } {
  const shareRaw = q.share === undefined ? '100' : String(q.share);
  const amountRaw = q.amount === undefined ? '0' : String(q.amount);
  const shareNum = Number(shareRaw);
  const amountNum = Number(amountRaw);
  let parts = '';
  let error: { status: string; status_code: number; message: string } | undefined;

  if (!Number.isNaN(shareNum)) {
    if (shareNum > 0 && shareNum <= 100) {
      parts += `&share=${shareNum}`;
    } else {
      error = { status: 'fail', status_code: 1007, message: 'error: share is not an integer between [1,100]' };
    }
  }
  if (!Number.isNaN(amountNum) && amountNum > 0) {
    parts += `&amount=${amountNum}`;
  } else if (q.share === undefined) {
    error = { status: 'fail', status_code: 1009, message: 'Please specify a share or amount (amount>0) parameters.' };
  }
  return { params: parts, error };
}

/**
 * @openapi
 * /aaveV3/lend:
 *   post:
 *     summary: (weak-auth sub-router) Lend into Aave v3 — see requests/lend.ts for the trader-verified equivalent
 *     tags: [Lending]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - $ref: '#/components/parameters/AssetParam'
 *       - $ref: '#/components/parameters/ShareParam'
 *       - $ref: '#/components/parameters/AmountParam'
 *     responses:
 *       200:
 *         description: >-
 *           Success, or a validation failure. Failures return status="fail"
 *           with status_code 1000 (network), 1001 (protocol), 1002 (apiKey)
 *           or 1004 (pool address).
 */
router.post('/aaveV3/lend', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');
  const platform = 'aavev3';

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const { params, error } = buildShareAmountParams(q);
  if (error) return res.json(error);

  const url = `${EXPRESS_BASE}lendRaw?apiKey=${encodeURIComponent(apiKey)}&protocol=${protocol}&pool=${pool}&network=${network}&asset=${encodeURIComponent(asset)}&platform=${platform}${params}`;
  return res.json(await proxyPost(url));
});

/**
 * @openapi
 * /aaveV3/unlend:
 *   post:
 *     summary: (weak-auth sub-router) Withdraw from Aave v3 — see requests/unlend.ts for the trader-verified equivalent
 *     tags: [Lending]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - $ref: '#/components/parameters/AssetParam'
 *       - $ref: '#/components/parameters/ShareParam'
 *       - $ref: '#/components/parameters/AmountParam'
 *     responses:
 *       200:
 *         description: >-
 *           Success, or a validation failure. Failures return status="fail"
 *           with status_code 1000 (network), 1001 (protocol), 1002 (apiKey)
 *           or 1004 (pool address).
 */
router.post('/aaveV3/unlend', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');
  const platform = 'aavev3';

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const { params, error } = buildShareAmountParams(q);
  if (error) return res.json(error);

  const url = `${EXPRESS_BASE}unlendRaw?apiKey=${encodeURIComponent(apiKey)}&protocol=${protocol}&pool=${pool}&network=${network}&asset=${encodeURIComponent(asset)}&platform=${platform}${params}`;
  return res.json(await proxyPost(url));
});

/**
 * @openapi
 * /aaveV3/borrow:
 *   post:
 *     summary: (weak-auth sub-router) Borrow from Aave v3 — see requests/borrow.ts for the trader-verified equivalent
 *     tags: [Lending]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - $ref: '#/components/parameters/AssetParam'
 *       - $ref: '#/components/parameters/ShareParam'
 *       - $ref: '#/components/parameters/AmountParam'
 *     responses:
 *       200:
 *         description: >-
 *           Success, or a validation failure. Failures return status="fail"
 *           with status_code 1000 (network), 1001 (protocol), 1002 (apiKey)
 *           or 1004 (pool address).
 */
router.post('/aaveV3/borrow', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');
  const platform = 'aavev3';

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const amountRaw = q.amount === undefined ? '0' : String(q.amount);
  const amountNum = Number(amountRaw);
  if (!Number.isNaN(amountNum) && amountNum > 0) {
    const amount = Math.round(amountNum * 100) / 100;
    const url = `${EXPRESS_BASE}borrowRaw?apiKey=${encodeURIComponent(apiKey)}&protocol=${protocol}&pool=${pool}&network=${network}&asset=${encodeURIComponent(asset)}&platform=${platform}&amount=${amount}`;
    return res.json(await proxyPost(url));
  }
  return res.json({ status: 'fail', error_code: 1009, message: 'Please specify a valid amount (amount>0) parameter.' });
});

/**
 * @openapi
 * /aaveV3/repay:
 *   post:
 *     summary: (weak-auth sub-router) Repay to Aave v3 — see requests/repay.ts for the trader-verified equivalent
 *     tags: [Lending]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - $ref: '#/components/parameters/AssetParam'
 *       - $ref: '#/components/parameters/ShareParam'
 *       - $ref: '#/components/parameters/AmountParam'
 *     responses:
 *       200:
 *         description: >-
 *           Success, or a validation failure. Failures return status="fail"
 *           with status_code 1000 (network), 1001 (protocol), 1002 (apiKey)
 *           or 1004 (pool address).
 */
router.post('/aaveV3/repay', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');
  const platform = 'aavev3';

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const { params, error } = buildShareAmountParams(q);
  if (error) return res.json(error);

  const url = `${EXPRESS_BASE}repayRaw?apiKey=${encodeURIComponent(apiKey)}&protocol=${protocol}&pool=${pool}&network=${network}&asset=${encodeURIComponent(asset)}&platform=${platform}${params}`;
  return res.json(await proxyPost(url));
});

/**
 * @openapi
 * /aaveV3/getPoolData:
 *   get:
 *     summary: (weak-auth sub-router) Get full Aave v3 pool data
 *     tags: [Lending]
 */
router.get('/aaveV3/getPoolData', async (req: Request, res: Response) => {
  const q = req.query as any;
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  // R's aaveV3$getPoolData calls port-8002's /getPoolAaveData (== our
  // getPoolAaveDataRaw), but WITHOUT resolving/passing contractAddress — it
  // just forwards apiKey/protocol/pool/network. Since /getPoolAaveDataRaw
  // requires contractAddress, we resolve it the same way
  // getPoolAaveData.ts's public wrapper does, so this sub-router endpoint
  // actually works rather than always failing on a missing param.
  const { poolComp } = await import('../tradeEngine');
  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }
  const row = composition.find((r) => (r.symbol || '').toLowerCase() === 'aavev3');
  if (!row) {
    return res.json({ status: 'fail', status_code: 400, message: "platform 'AAVEV3' is not enabled inside the vault" });
  }
  const url = `${EXPRESS_BASE}getPoolAaveDataRaw?pool=${pool}&network=${network}&contractAddress=${row.asset}`;
  return res.json(await proxyGet(url));
});

/**
 * @openapi
 * /aaveV3/getHealthFactor:
 *   get:
 *     summary: (weak-auth sub-router) Get the Aave v3 health factor
 *     tags: [Lending]
 */
router.get('/aaveV3/getHealthFactor', async (req: Request, res: Response) => {
  const q = req.query as any;
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const platform = 'aavev3';

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const { poolComp } = await import('../tradeEngine');
  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }
  const row = composition.find((r) => (r.symbol || '').toLowerCase() === platform);
  if (!row) {
    return res.json({ status: 'fail', status_code: 400, message: `platform '${platform}' is not enabled inside the vault` });
  }
  const url = `${EXPRESS_BASE}getHealthFactorRaw?pool=${pool}&network=${network}&platform=${platform}&contractAddress=${row.asset}`;
  return res.json(await proxyGet(url));
});

/**
 * @openapi
 * /aaveV3/getBorrowed:
 *   get:
 *     summary: (weak-auth sub-router) Get total borrowed amount on Aave v3
 *     tags: [Lending]
 */
router.get('/aaveV3/getBorrowed', async (req: Request, res: Response) => {
  const q = req.query as any;
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  // Mirrors getBorrowedHandler (port 8002): resolve asset via get_contract(),
  // then resolve platform_contract ("AAVEV3") via pool composition, before
  // calling Express's own /getBorrowed with both contractAddress and asset.
  const assetContract = await getContract(asset, network);
  if (!assetContract) {
    return res.json({ status: 'fail', status_code: 400, message: `Unable to resolve asset contract for '${asset}' on network '${network}'` });
  }
  const { poolComp } = await import('../tradeEngine');
  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }
  const row = composition.find((r) => (r.symbol || '').toLowerCase() === 'aavev3');
  if (!row) {
    return res.json({ status: 'fail', status_code: 400, message: 'AAVEV3 is not enabled inside the vault' });
  }

  const url = `${EXPRESS_BASE}getBorrowed?pool=${pool}&network=${network}&contractAddress=${row.asset}&asset=${assetContract}`;
  return res.json(await proxyGet(url));
});

/**
 * @openapi
 * /aaveV3/getSupplied:
 *   get:
 *     summary: (weak-auth sub-router) Get total supplied amount on Aave v3
 *     tags: [Lending]
 */
router.get('/aaveV3/getSupplied', async (req: Request, res: Response) => {
  const q = req.query as any;
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const asset = String(q.asset || '');

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  const assetContract = await getContract(asset, network);
  if (!assetContract) {
    return res.json({ status: 'fail', status_code: 400, message: `Unable to resolve asset contract for '${asset}' on network '${network}'` });
  }
  const { poolComp } = await import('../tradeEngine');
  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) {
    return res.json({ status: 'fail', status_code: 400, message: 'unable to fetch pool composition' });
  }
  const row = composition.find((r) => (r.symbol || '').toLowerCase() === 'aavev3');
  if (!row) {
    return res.json({ status: 'fail', status_code: 400, message: "'AAVEV3' is not enabled inside the vault" });
  }

  const url = `${EXPRESS_BASE}getSupplied?pool=${pool}&network=${network}&contractAddress=${row.asset}&asset=${assetContract}`;
  return res.json(await proxyGet(url));
});

export default router;
