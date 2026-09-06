/**
 * mintManagerFeeBatch.ts — batched manager-fee minting.
 *
 * WHY THIS EXISTS
 * ---------------
 * The existing GET /mintManagerFee (admin.ts) mints the accrued manager fee for
 * exactly ONE pool, costing one transaction (and one gas payment) per vault.
 * Operators running many vaults (e.g. every Infinite Trading DAO managed vault)
 * previously had to fire N separate transactions.
 *
 * PoolLogic.mintManagerFee() is PERMISSIONLESS on dHEDGE — it can be called by
 * any address, it simply realises the already-accrued fee and mints the manager
 * their share. (Verified on-chain via an eth_call from a random address, which
 * succeeds.) That property is what makes batching possible: we can route every
 * pool's mintManagerFee() call through Multicall3's aggregate3() so that all of
 * them land in a SINGLE on-chain transaction, paying gas once.
 *
 * Multicall3 (0xcA11bde05977b3631167028862bE2a173976CA11) is deployed at the
 * same address on every network we support, and is already used elsewhere in
 * this codebase (admin.ts batchGetPoolCompositions) for read batching.
 *
 * ENDPOINT
 * --------
 *   GET|POST /mintManagerFeeBatch
 *     pools    (required) comma-separated pool addresses, or repeated ?pools=
 *              params, or a JSON array in the POST body.
 *     network  (required) e.g. optimism / polygon / base / arbitrum
 *     apiKey   (required) the gas-wallet API token that pays for the tx.
 *     protocol (optional, default dhedge) — validated for parity with the rest
 *              of the public API surface.
 *     dryRun   (optional, default false) — simulate only, submit nothing.
 *     allowFailure (optional, default true) — when true a single pool that
 *              reverts does NOT abort the whole batch; its per-pool result is
 *              reported as failed and the others still mint. Set false for
 *              all-or-nothing semantics.
 *
 * VALIDATION
 * ----------
 * Mirrors the rest of the migrated public surface: basicCheck() for
 * network/protocol/apiKey format, then every pool address is format-checked.
 * Since mintManagerFee is permissionless there is deliberately NO isValidTrader
 * check — requiring pool-trader ownership would be stricter than the on-chain
 * contract itself and would block the legitimate "mint fees for all DAO vaults"
 * use case. The apiKey is still required because it identifies the gas wallet
 * that pays, and it is what apiPayment() bills.
 */

import { Router, Request, Response } from 'express';
import { ethers } from 'ethers';
import { Network } from '@dhedge/v2-sdk';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';
import { walletv2 } from '../walletv2';
import { getAllRpcProviders } from '../rpc';
import { createRetryProviderWithFailover } from '../utils/RetryProvider';
import { txFees, apiPayment } from '../txFees';
import { notifyTelegram } from '../utils/telegram';

const router = Router();

const MULTICALL3_ADDRESS = '0xcA11bde05977b3631167028862bE2a173976CA11';
const MULTICALL3_ABI = [
  'function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) payable returns (tuple(bool success, bytes returnData)[] returnData)',
];
const POOL_ABI = [
  'function mintManagerFee()',
  'function availableManagerFee() view returns (uint256)',
  'function name() view returns (string)',
];

/** Accepts ?pools=a,b,c / repeated ?pools=a&pools=b / JSON array body. */
function parsePools(raw: unknown): string[] {
  if (raw === undefined || raw === null) return [];
  const flat: string[] = Array.isArray(raw)
    ? raw.flatMap(v => String(v).split(','))
    : String(raw).split(',');
  return flat.map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
}

function parseBool(v: unknown, dflt: boolean): boolean {
  if (v === undefined || v === null || v === '') return dflt;
  if (typeof v === 'boolean') return v;
  return String(v).toLowerCase() === 'true';
}

/**
 * @openapi
 * /mintManagerFeeBatch:
 *   get:
 *     summary: Mint accrued manager fees for many vaults in ONE transaction
 *     description: >
 *       Batches PoolLogic.mintManagerFee() calls for every supplied pool into a
 *       single Multicall3 aggregate3 transaction, so N vaults cost one tx and
 *       one gas payment instead of N. mintManagerFee is permissionless on
 *       dHEDGE, so the caller does not need to be the manager of each vault.
 *     tags: [Admin]
 *     parameters:
 *       - in: query
 *         name: pools
 *         required: true
 *         description: Comma-separated pool addresses (or repeat the param).
 *         schema: { type: string }
 *       - in: query
 *         name: network
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: apiKey
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: protocol
 *         schema: { type: string, default: dhedge }
 *       - in: query
 *         name: dryRun
 *         description: Simulate only; do not submit a transaction.
 *         schema: { type: boolean, default: false }
 *       - in: query
 *         name: allowFailure
 *         description: Let individual pools fail without aborting the batch.
 *         schema: { type: boolean, default: true }
 *     responses:
 *       200:
 *         description: Batch simulated (dryRun) or submitted.
 */
async function handleBatch(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };

  const network = String(q.network || '').toLowerCase();
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const dryRun = parseBool(q.dryRun, false);
  const allowFailure = parseBool(q.allowFailure, true);
  const pools = parsePools(q.pools ?? q.pool);

  // ── Validation (same shape/order as every other migrated public endpoint) ──
  const check = await basicCheck({ network, protocol, apiKey });
  if (check.status === 'fail') return res.status(200).send(toRWireFormat(check));

  if (pools.length === 0) {
    return res.status(200).send(toRWireFormat({
      status: 'fail', status_code: '1010',
      message: 'error: pools parameter is required (comma-separated pool addresses)',
    }));
  }
  for (const p of pools) {
    if (!isValidEthereumAddress(p)) {
      return res.status(200).send(toRWireFormat({
        status: 'fail', status_code: '1004',
        message: `Invalid Pool Address: ${p}`,
      }));
    }
  }
  // Duplicate pools would just waste gas minting twice; collapse them.
  const uniquePools = [...new Set(pools)];

  try {
    const net = network as Network;
    const provider = createRetryProviderWithFailover(getAllRpcProviders(net));
    const poolIface = new ethers.utils.Interface(POOL_ABI);
    const callData = poolIface.encodeFunctionData('mintManagerFee', []);

    // ── Pre-flight: report the fee currently available per pool ──────────────
    // availableManagerFee() is a view; batching it through Multicall3 keeps this
    // to a single RPC round-trip even for dozens of vaults. Pools that revert
    // (older PoolLogic versions do not expose it) are reported as "unknown"
    // rather than failing the request.
    const multicallRead = new ethers.Contract(MULTICALL3_ADDRESS, MULTICALL3_ABI, provider);
    const readCalls = uniquePools.map(p => ({
      target: p, allowFailure: true,
      callData: poolIface.encodeFunctionData('availableManagerFee', []),
    }));
    let available: (string | null)[] = uniquePools.map(() => null);
    try {
      const readRes = await multicallRead.callStatic.aggregate3(readCalls);
      available = readRes.map((r: any) => {
        if (!r.success) return null;
        try {
          return poolIface.decodeFunctionResult('availableManagerFee', r.returnData)[0].toString();
        } catch { return null; }
      });
    } catch (e: any) {
      console.log('/mintManagerFeeBatch: availableManagerFee pre-flight failed:', e?.message);
    }

    const calls = uniquePools.map(p => ({ target: p, allowFailure, callData }));

    // ── Simulate the whole batch before spending anything ────────────────────
    const signer = await walletv2(net, apiKey, null, null);
    const multicall = new ethers.Contract(MULTICALL3_ADDRESS, MULTICALL3_ABI, signer);

    let simulation: any[];
    try {
      simulation = await multicall.callStatic.aggregate3(calls);
    } catch (e: any) {
      const msg = e?.message || String(e);
      return res.status(400).send({
        status: 'fail', status_code: 3011,
        message: `Batch simulation reverted — nothing submitted: ${msg.substring(0, 300)}`,
        error_type: 'mint_manager_fee_batch_failed',
      });
    }

    const perPool = uniquePools.map((p, i) => ({
      pool: p,
      willSucceed: simulation[i]?.success ?? false,
      availableManagerFee: available[i],
    }));

    if (dryRun) {
      return res.status(200).send({
        status: 'success',
        dryRun: true,
        network,
        count: uniquePools.length,
        wouldSucceed: perPool.filter(r => r.willSucceed).length,
        results: perPool,
      });
    }

    // If every pool would revert there is no point paying for a transaction.
    if (!perPool.some(r => r.willSucceed)) {
      return res.status(400).send({
        status: 'fail', status_code: 3012,
        message: 'No pool in the batch would succeed — transaction not submitted.',
        error_type: 'mint_manager_fee_batch_failed',
        results: perPool,
      });
    }

    // ── Submit the single batched transaction ───────────────────────────────
    const estimatedGas = await multicall.estimateGas.aggregate3(calls);
    const txOptions = await txFees(net, null, null, estimatedGas);
    const tx = await multicall.aggregate3(calls, txOptions);

    console.log(`/mintManagerFeeBatch: submitted ${uniquePools.length} pools in tx ${tx.hash}`);
    apiPayment(net, apiKey, tx, null, null, null);

    const okCount = perPool.filter(r => r.willSucceed).length;
    notifyTelegram(
      `✅ mintManagerFeeBatch | ${network} | ${okCount}/${uniquePools.length} vaults minted in ONE tx | ${tx.hash}`
    );

    return res.status(200).send({
      status: 'success',
      network,
      txHash: tx.hash,
      count: uniquePools.length,
      minted: okCount,
      results: perPool,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('/mintManagerFeeBatch error:', message);
    notifyTelegram(`❌ mintManagerFeeBatch failed | ${network} | ${message.substring(0, 200)}`);
    return res.status(400).send({
      status: 'fail', status_code: 3013,
      message, error_type: 'mint_manager_fee_batch_failed',
    });
  }
}

router.get('/mintManagerFeeBatch', handleBatch);
router.post('/mintManagerFeeBatch', handleBatch);

export default router;
