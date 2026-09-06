/**
 * mintAllFeesByManager.ts — mint every accrued manager fee for one manager,
 * in a single transaction.
 *
 * WHY THIS EXISTS
 * ---------------
 * /mintManagerFeeBatch already batches many vaults into one Multicall3 tx, but
 * the caller has to supply the pool addresses by hand as a comma-separated
 * list. That list goes stale the moment a vault is added or retired, and
 * nobody maintaining "mint all the DAO's fees" wants to curate it.
 *
 * This endpoint takes a MANAGER address instead and discovers the vaults
 * itself, so the caller never names a pool.
 *
 * HOW DISCOVERY WORKS
 * -------------------
 * The `gas_wallets` table has a `manager` column, but it is empty for nearly
 * every row in production, so it cannot be trusted as the source of truth.
 * Instead we treat `gas_wallets` as the candidate SET (the vaults this system
 * knows about on a given network) and resolve the real manager ON-CHAIN:
 *
 *     pool -> poolManagerLogic() -> manager()
 *
 * On-chain is authoritative: it reflects manager transfers immediately and
 * cannot drift from reality the way a cached column does.
 *
 * CONSEQUENCE, STATED PLAINLY: a vault managed by this manager that has no row
 * in `gas_wallets` will NOT be discovered, because this system has no other
 * record that it exists. The response therefore reports `scanned` alongside
 * `matched`, so the caller can see the size of the candidate set rather than
 * assuming "0 matched" means "no fees owed". Use /mintManagerFeeBatch with an
 * explicit pool list to reach a vault outside that set.
 *
 * ONLY FEES > 0
 * -------------
 * Every matched vault is quoted with calculateAvailableManagerFee() and any
 * vault with a zero fee is dropped BEFORE the transaction is built. Minting a
 * zero fee is a no-op that still costs gas and still consumes calldata, so
 * filtering keeps the batch as small and as cheap as possible.
 *
 * PERMISSIONLESS
 * --------------
 * PoolLogic.mintManagerFee() can be called by anyone; it realises the
 * already-accrued fee and mints the manager their share. That is what makes
 * this safe to expose: the caller cannot direct fees anywhere, they can only
 * cause the manager to be paid what the contract already owes them. There is
 * deliberately no isValidTrader check, which would be stricter than the
 * contract itself. The apiKey is still required: it identifies the gas wallet
 * that pays for the transaction and is what apiPayment() bills.
 *
 * ENDPOINT
 * --------
 *   GET|POST /mintAllFeesByManager
 *     manager  (required) the manager address whose vaults should be minted.
 *     network  (required) e.g. optimism / base / polygon / arbitrum
 *     apiKey   (required) gas-wallet API token that pays for the tx.
 *     protocol (optional, default dhedge; `chamber` also accepted)
 *     dryRun   (optional, default false) — discover and quote, submit nothing.
 *     allowFailure (optional, default true) — one reverting vault does not
 *              abort the rest of the batch.
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
import { dbQuery } from '../db';

const router = Router();

const MULTICALL3_ADDRESS = '0xcA11bde05977b3631167028862bE2a173976CA11';
const MULTICALL3_ABI = [
  'function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) payable returns (tuple(bool success, bytes returnData)[] returnData)',
];
const POOL_ABI = [
  'function mintManagerFee()',
  'function calculateAvailableManagerFee(uint256 fundValue) view returns (uint256)',
  'function poolManagerLogic() view returns (address)',
  'function name() view returns (string)',
];
const MANAGER_LOGIC_ABI = [
  'function totalFundValue() view returns (uint256)',
  'function manager() view returns (address)',
];

function parseBool(v: unknown, dflt: boolean): boolean {
  if (v === undefined || v === null || v === '') return dflt;
  if (typeof v === 'boolean') return v;
  return String(v).toLowerCase() === 'true';
}

/**
 * @openapi
 * /mintAllFeesByManager:
 *   get:
 *     summary: Mint every accrued fee for one manager's vaults in ONE transaction
 *     description: >
 *       Finds every known vault on the given network whose on-chain manager
 *       matches the supplied address, drops any vault with a zero available
 *       fee, and mints the rest in a single Multicall3 transaction. Unlike
 *       /mintManagerFeeBatch, the caller does not supply pool addresses.
 *       Vaults are discovered from this system's known-vault set and their
 *       manager is verified on-chain, so a vault unknown to this system will
 *       not be included -- compare `scanned` with `matched` in the response.
 *     tags: [Admin]
 *     parameters:
 *       - in: query
 *         name: manager
 *         required: true
 *         description: Manager address whose vaults should have fees minted.
 *         schema: { type: string, pattern: '^0x[a-fA-F0-9]{40}$' }
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - in: query
 *         name: dryRun
 *         description: Discover and quote fees only; submit no transaction.
 *         schema: { type: boolean, default: false }
 *       - in: query
 *         name: allowFailure
 *         description: Let individual vaults fail without aborting the batch.
 *         schema: { type: boolean, default: true }
 *     responses:
 *       200:
 *         description: Batch simulated (dryRun) or submitted.
 */
async function handleMintAllByManager(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };

  const network = String(q.network || '').toLowerCase();
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const apiKey = String(q.apiKey || '');
  const manager = String(q.manager || '').toLowerCase();
  const dryRun = parseBool(q.dryRun, false);
  const allowFailure = parseBool(q.allowFailure, true);

  const check = await basicCheck({ network, protocol, apiKey });
  if (check.status === 'fail') return res.status(200).send(toRWireFormat(check));

  if (!manager) {
    return res.status(200).send(toRWireFormat({
      status: 'fail', status_code: '1010',
      message: 'error: manager parameter is required (the manager address)',
    }));
  }
  if (!isValidEthereumAddress(manager)) {
    return res.status(200).send(toRWireFormat({
      status: 'fail', status_code: '1004',
      message: `Invalid Manager Address: ${manager}`,
    }));
  }

  try {
    const net = network as Network;

    // ── Candidate set: every vault this system knows about on this network ──
    const rows: any[] = await dbQuery(
      'SELECT DISTINCT pool FROM gas_wallets WHERE network = ? AND protocol = ? AND pool IS NOT NULL AND is_active = 1',
      [network, protocol]
    );
    const candidates = [...new Set(
      rows.map(r => String(r.pool || '').toLowerCase()).filter(isValidEthereumAddress)
    )];

    if (candidates.length === 0) {
      return res.status(200).send({
        status: 'fail', status_code: 3014,
        message: `No known vaults on ${network} to scan.`,
        error_type: 'mint_all_fees_by_manager_failed',
        scanned: 0, matched: 0,
      });
    }

    const provider = createRetryProviderWithFailover(getAllRpcProviders(net));
    const multicallRead = new ethers.Contract(MULTICALL3_ADDRESS, MULTICALL3_ABI, provider);
    const poolIface = new ethers.utils.Interface(POOL_ABI);
    const mlIface = new ethers.utils.Interface(MANAGER_LOGIC_ABI);

    // ── Stage 1: pool -> poolManagerLogic ───────────────────────────────────
    // Every stage is batched through Multicall3, so scanning N vaults costs a
    // fixed handful of RPC round-trips rather than N.
    const plmRes = await multicallRead.callStatic.aggregate3(
      candidates.map(p => ({
        target: p, allowFailure: true,
        callData: poolIface.encodeFunctionData('poolManagerLogic', []),
      }))
    );
    const managerLogics = plmRes.map((r: any) => {
      if (!r.success) return null;
      try { return poolIface.decodeFunctionResult('poolManagerLogic', r.returnData)[0] as string; }
      catch { return null; }
    });

    // ── Stage 2: poolManagerLogic -> manager(), and keep only OUR manager ───
    const mgrRes = await multicallRead.callStatic.aggregate3(
      managerLogics.map((ml: string | null) => ({
        target: ml || MULTICALL3_ADDRESS, allowFailure: true,
        callData: mlIface.encodeFunctionData('manager', []),
      }))
    );
    const owned: { pool: string; managerLogic: string }[] = [];
    mgrRes.forEach((r: any, i: number) => {
      if (!managerLogics[i] || !r.success) return;
      try {
        const m = (mlIface.decodeFunctionResult('manager', r.returnData)[0] as string).toLowerCase();
        if (m === manager) owned.push({ pool: candidates[i], managerLogic: managerLogics[i]! });
      } catch { /* undecodable -> not a vault we can act on */ }
    });

    if (owned.length === 0) {
      return res.status(200).send({
        status: 'success',
        network, manager,
        scanned: candidates.length, matched: 0, eligible: 0,
        message: `No vaults on ${network} are managed by ${manager} within this system's known-vault set.`,
        results: [],
      });
    }

    // ── Stage 3+4: quote the available fee for each matched vault ───────────
    const fvRes = await multicallRead.callStatic.aggregate3(
      owned.map(o => ({
        target: o.managerLogic, allowFailure: true,
        callData: mlIface.encodeFunctionData('totalFundValue', []),
      }))
    );
    const fundValues = fvRes.map((r: any) => {
      if (!r.success) return null;
      try { return mlIface.decodeFunctionResult('totalFundValue', r.returnData)[0]; }
      catch { return null; }
    });

    const feeRes = await multicallRead.callStatic.aggregate3(
      owned.map((o, i) => ({
        target: o.pool, allowFailure: true,
        callData: poolIface.encodeFunctionData('calculateAvailableManagerFee', [fundValues[i] ?? 0]),
      }))
    );
    const nameRes = await multicallRead.callStatic.aggregate3(
      owned.map(o => ({
        target: o.pool, allowFailure: true,
        callData: poolIface.encodeFunctionData('name', []),
      }))
    );

    const quoted = owned.map((o, i) => {
      let fee: ethers.BigNumber | null = null;
      if (fundValues[i] && feeRes[i]?.success) {
        try {
          fee = poolIface.decodeFunctionResult(
            'calculateAvailableManagerFee', feeRes[i].returnData
          )[0] as ethers.BigNumber;
        } catch { fee = null; }
      }
      let name: string | null = null;
      if (nameRes[i]?.success) {
        try { name = poolIface.decodeFunctionResult('name', nameRes[i].returnData)[0] as string; }
        catch { name = null; }
      }
      return {
        pool: o.pool,
        name,
        availableManagerFee: fee ? fee.toString() : null,
        // A vault we could not quote is treated as ineligible rather than
        // optimistically included: better to skip a mint than to pay gas for
        // a call we have no evidence will do anything.
        hasFee: fee !== null && fee.gt(0),
      };
    });

    const eligible = quoted.filter(v => v.hasFee);

    if (eligible.length === 0) {
      return res.status(200).send({
        status: 'success',
        network, manager,
        scanned: candidates.length,
        matched: owned.length,
        eligible: 0,
        message: 'No vault for this manager has a non-zero available fee — nothing to mint.',
        results: quoted,
      });
    }

    // ── Build and simulate the single batched transaction ────────────────────
    const callData = poolIface.encodeFunctionData('mintManagerFee', []);
    const calls = eligible.map(v => ({ target: v.pool, allowFailure, callData }));

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
        error_type: 'mint_all_fees_by_manager_failed',
      });
    }

    const perPool = eligible.map((v, i) => ({
      ...v,
      willSucceed: simulation[i]?.success ?? false,
    }));

    if (dryRun) {
      return res.status(200).send({
        status: 'success',
        dryRun: true,
        network, manager,
        scanned: candidates.length,
        matched: owned.length,
        eligible: eligible.length,
        wouldSucceed: perPool.filter(r => r.willSucceed).length,
        results: perPool,
        skipped: quoted.filter(v => !v.hasFee),
      });
    }

    if (!perPool.some(r => r.willSucceed)) {
      return res.status(400).send({
        status: 'fail', status_code: 3012,
        message: 'No vault in the batch would succeed — transaction not submitted.',
        error_type: 'mint_all_fees_by_manager_failed',
        results: perPool,
      });
    }

    const estimatedGas = await multicall.estimateGas.aggregate3(calls);
    const txOptions = await txFees(net, null, null, estimatedGas);
    const tx = await multicall.aggregate3(calls, txOptions);

    console.log(
      `/mintAllFeesByManager: manager=${manager} network=${network} ` +
      `submitted ${eligible.length} vaults in tx ${tx.hash}`
    );
    apiPayment(net, apiKey, tx, null, null, null);

    const okCount = perPool.filter(r => r.willSucceed).length;
    notifyTelegram(
      `✅ mintAllFeesByManager | ${network} | manager ${manager} | ` +
      `${okCount}/${eligible.length} vaults minted in ONE tx | ${tx.hash}`
    );

    return res.status(200).send({
      status: 'success',
      network, manager,
      txHash: tx.hash,
      scanned: candidates.length,
      matched: owned.length,
      eligible: eligible.length,
      minted: okCount,
      results: perPool,
      skipped: quoted.filter(v => !v.hasFee),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('/mintAllFeesByManager error:', message);
    notifyTelegram(`❌ mintAllFeesByManager failed | ${network} | ${message.substring(0, 200)}`);
    return res.status(400).send({
      status: 'fail', status_code: 3013,
      message, error_type: 'mint_all_fees_by_manager_failed',
    });
  }
}

router.get('/mintAllFeesByManager', handleMintAllByManager);
router.post('/mintAllFeesByManager', handleMintAllByManager);

export default router;
