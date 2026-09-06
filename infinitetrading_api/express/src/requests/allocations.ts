/**
 * requests/allocations.ts — index-vault allocation targets and rebalancing.
 *
 * The goal: treat a dHEDGE vault as an index. You declare target weights
 * ("WBTC 50%, WETH 50%"), a tolerance band per asset, and the API works out
 * what to trade to bring the vault back to those weights.
 *
 * Three endpoints:
 *   POST /setAllocations        — store the target weights for a vault
 *   GET  /getCurrentAllocations — targets alongside LIVE weights and drift
 *   POST /rebalancePool         — compute (and optionally execute) the trades
 *
 * These replace R gateway stubs that were never finished: setAllocations
 * validated its inputs and wrote a row, getCurrentAllocations echoed that row
 * back, and rebalancePool returned "Endpoint not available yet". Notably the R
 * version accepted `slippages` and `max_usd`, validated them, and then dropped
 * them -- the INSERT never stored those columns. They are persisted now, since
 * a rebalancer needs them.
 *
 * DESIGN NOTES
 *
 * Parallel "-" delimited strings (assets=WBTC-WETH, allocations=50-50) are the
 * wire format the R endpoints used and what the table stores, so it is kept
 * for compatibility. A JSON body is also accepted because the positional
 * format is easy to get wrong; both parse to the same internal shape.
 *
 * Weights must sum to 100. R never checked this, so "50-50-50" was storable
 * and would have produced a permanently unreachable target.
 *
 * Rebalancing is DRY-RUN BY DEFAULT (execute=false). It moves real funds, so
 * the caller has to ask for it explicitly. The plan it returns is the same one
 * it would execute.
 *
 * Sells are executed before buys. Selling first frees the stablecoin the buys
 * need, so a vault that is fully invested can still rebalance; doing it the
 * other way round means the buys fail for lack of funds.
 */

import { Router, Request, Response } from 'express';
import { dbQuery } from '../db';
import { basicCheck, toRWireFormat } from '../basicCheck';
import { requireLendingAuth } from '../lendingAuth';
import { poolComp } from '../tradeEngine';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';

/** Hard ceiling on a single rebalance, mirroring R's original guard. */
const MAX_USD_LIMIT = 100_000_000;

interface AllocationTarget {
  asset: string;
  allocation: number;
  lowerThreshold: number;
  upperThreshold: number;
  slippage: number;
}

function splitList(v: unknown): string[] {
  return String(v ?? '')
    .split('-')
    .map((x) => x.trim())
    .filter((x) => x.length > 0);
}

function fail(status_code: number, message: string) {
  return { status: 'fail', status_code, message };
}

/**
 * Parses either the "-" delimited form or a JSON `targets` array into one
 * shape, so the rest of the handler does not care which the caller used.
 */
function parseTargets(q: any): { targets?: AllocationTarget[]; error?: any } {
  if (Array.isArray(q.targets)) {
    const targets: AllocationTarget[] = [];
    for (const t of q.targets) {
      const asset = String(t?.asset ?? '').toUpperCase();
      if (!asset) return { error: fail(400, 'Each target needs an asset symbol') };
      targets.push({
        asset,
        allocation: Number(t?.allocation),
        lowerThreshold: t?.lowerThreshold === undefined ? 5 : Number(t.lowerThreshold),
        upperThreshold: t?.upperThreshold === undefined ? 5 : Number(t.upperThreshold),
        slippage: t?.slippage === undefined ? 0.5 : Number(t.slippage),
      });
    }
    return { targets };
  }

  const assets = splitList(q.assets).map((a) => a.toUpperCase());
  if (assets.length === 0) {
    return { error: fail(400, 'assets is required, e.g. assets=WBTC-WETH') };
  }

  const allocations = splitList(q.allocations).map(Number);
  // Thresholds and slippages are optional; a single value applies to every
  // asset, which is the common case and avoids "5-5-5-5-5".
  const lower = splitList(q.lower_thresholds).map(Number);
  const upper = splitList(q.upper_thresholds).map(Number);
  const slippages = splitList(q.slippages).map(Number);

  if (allocations.length !== assets.length) {
    return {
      error: fail(
        400,
        `assets has ${assets.length} entries but allocations has ${allocations.length}; they must match`
      ),
    };
  }

  const expand = (arr: number[], dflt: number, name: string): number[] | { error: any } => {
    if (arr.length === 0) return assets.map(() => dflt);
    if (arr.length === 1) return assets.map(() => arr[0]);
    if (arr.length !== assets.length) {
      return {
        error: fail(
          400,
          `${name} must have 1 value (applied to all) or ${assets.length} values, got ${arr.length}`
        ),
      };
    }
    return arr;
  };

  const lowerX = expand(lower, 5, 'lower_thresholds');
  if (!Array.isArray(lowerX)) return { error: lowerX.error };
  const upperX = expand(upper, 5, 'upper_thresholds');
  if (!Array.isArray(upperX)) return { error: upperX.error };
  const slipX = expand(slippages, 0.5, 'slippages');
  if (!Array.isArray(slipX)) return { error: slipX.error };

  return {
    targets: assets.map((asset, i) => ({
      asset,
      allocation: allocations[i],
      lowerThreshold: lowerX[i],
      upperThreshold: upperX[i],
      slippage: slipX[i],
    })),
  };
}

function validateTargets(targets: AllocationTarget[]): any | null {
  const seen = new Set<string>();
  for (const t of targets) {
    if (seen.has(t.asset)) return fail(400, `Duplicate asset '${t.asset}' in allocations`);
    seen.add(t.asset);

    for (const [label, v, min, max] of [
      ['allocation', t.allocation, 0, 100],
      ['lowerThreshold', t.lowerThreshold, 0, 100],
      ['upperThreshold', t.upperThreshold, 0, 100],
      ['slippage', t.slippage, 0, 100],
    ] as [string, number, number, number][]) {
      if (!Number.isFinite(v)) return fail(400, `${label} for ${t.asset} must be numeric`);
      if (v < min || v > max) return fail(400, `${label} for ${t.asset} must be between ${min} and ${max}`);
    }
  }

  // Guards against a target that can never be satisfied. R did not check this.
  const total = targets.reduce((s, t) => s + t.allocation, 0);
  if (Math.abs(total - 100) > 0.01) {
    return fail(400, `allocations must sum to 100, got ${Math.round(total * 100) / 100}`);
  }
  return null;
}

/**
 * @openapi
 * /setAllocations:
 *   post:
 *     summary: Set the target index allocations for a vault
 *     description: >-
 *       Stores target weights for a vault so it can be rebalanced like an
 *       index fund. Weights must sum to 100. Supply either the "-" delimited
 *       parameters or a JSON body with a `targets` array. Thresholds define
 *       the tolerance band before an asset is considered out of balance;
 *       passing a single value applies it to every asset.
 *     tags: [Allocations]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - in: query
 *         name: assets
 *         description: Asset symbols separated by "-", e.g. WBTC-WETH
 *         schema: { type: string, example: 'WBTC-WETH' }
 *       - in: query
 *         name: allocations
 *         description: Target percentages separated by "-". Must sum to 100.
 *         schema: { type: string, example: '50-50' }
 *       - in: query
 *         name: lower_thresholds
 *         description: Drift below target tolerated, in percentage points. One value or one per asset.
 *         schema: { type: string, example: '5' }
 *       - in: query
 *         name: upper_thresholds
 *         description: Drift above target tolerated, in percentage points. One value or one per asset.
 *         schema: { type: string, example: '5' }
 *       - in: query
 *         name: slippages
 *         description: Max slippage per asset when rebalancing. One value or one per asset.
 *         schema: { type: string, example: '0.5' }
 *       - in: query
 *         name: max_usd
 *         description: Ceiling on USD traded in a single rebalance.
 *         schema: { type: number, example: 10000 }
 *       - $ref: '#/components/parameters/PlatformParam'
 *     responses:
 *       200:
 *         description: Allocations stored, echoing the parsed targets.
 */
router.post('/setAllocations', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };

  const auth = await requireLendingAuth(req);
  if (!auth.ok) return res.json(auth.body);
  const { protocol, pool, network } = auth;

  const { targets, error } = parseTargets(q);
  if (error) return res.json(error);
  const invalid = validateTargets(targets!);
  if (invalid) return res.json(invalid);

  const maxUsd = q.max_usd === undefined ? 0 : Number(q.max_usd);
  if (!Number.isFinite(maxUsd) || maxUsd < 0) {
    return res.json(fail(400, 'max_usd must be numeric and >= 0'));
  }
  if (maxUsd > MAX_USD_LIMIT) {
    return res.json(fail(400, `max_usd must be <= ${MAX_USD_LIMIT}`));
  }
  const platform = String(q.platform || 'auto').toLowerCase();

  try {
    await dbQuery(
      `INSERT INTO dhedge_allocations
         (network, pool, assets, allocations, upper_thresholds, lower_thresholds,
          slippages, max_usd, platform, protocol)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         assets=VALUES(assets), allocations=VALUES(allocations),
         upper_thresholds=VALUES(upper_thresholds), lower_thresholds=VALUES(lower_thresholds),
         slippages=VALUES(slippages), max_usd=VALUES(max_usd),
         platform=VALUES(platform), protocol=VALUES(protocol)`,
      [
        network,
        pool,
        targets!.map((t) => t.asset).join('-'),
        targets!.map((t) => t.allocation).join('-'),
        targets!.map((t) => t.upperThreshold).join('-'),
        targets!.map((t) => t.lowerThreshold).join('-'),
        targets!.map((t) => t.slippage).join('-'),
        maxUsd,
        platform,
        protocol,
      ]
    );

    return res.json({
      status: 'success',
      status_code: 200,
      message: 'Allocations stored',
      data: { network, pool, protocol, platform, max_usd: maxUsd, targets },
    });
  } catch (e: any) {
    console.log(`Error: setAllocations pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json(fail(500, 'Internal error storing allocations'));
  }
});

/** Reads the stored row and reshapes it into the target array. */
async function loadTargets(
  network: string,
  pool: string
): Promise<{ targets: AllocationTarget[]; maxUsd: number; platform: string } | null> {
  const rows = await dbQuery(
    `SELECT assets, allocations, upper_thresholds, lower_thresholds, slippages, max_usd, platform
       FROM dhedge_allocations WHERE network = ? AND pool = ?`,
    [network, pool]
  );
  if (!rows || rows.length === 0) return null;
  const r: any = rows[0];

  const assets = splitList(r.assets);
  const allocations = splitList(r.allocations).map(Number);
  const upper = splitList(r.upper_thresholds).map(Number);
  const lower = splitList(r.lower_thresholds).map(Number);
  const slip = splitList(r.slippages).map(Number);

  return {
    targets: assets.map((asset, i) => ({
      asset: asset.toUpperCase(),
      allocation: allocations[i] ?? 0,
      // Rows written before these columns existed have no values; fall back
      // rather than emitting NaN.
      upperThreshold: Number.isFinite(upper[i]) ? upper[i] : 5,
      lowerThreshold: Number.isFinite(lower[i]) ? lower[i] : 5,
      slippage: Number.isFinite(slip[i]) ? slip[i] : 0.5,
    })),
    maxUsd: Number(r.max_usd) || 0,
    platform: String(r.platform || 'auto'),
  };
}

/**
 * Compares stored targets against live composition.
 *
 * Returns current weight, drift, and whether each asset is outside its band,
 * which is what both getCurrentAllocations and rebalancePool need.
 */
async function computeDrift(
  pool: string,
  network: string,
  protocol: string,
  apiKey: string,
  targets: AllocationTarget[]
) {
  const composition = await poolComp(pool, network, protocol, apiKey);
  if (!composition || composition.length === 0) return null;

  const totalValue = composition.reduce((s, r) => s + r.amount * r.price, 0);

  // An empty vault has no weights to drift, and every target would otherwise
  // read as -100% out of band while producing a zero-value (and therefore
  // empty) trade plan. Report it as balanced instead of contradicting itself.
  const isEmpty = totalValue <= 0;

  const bySymbol = new Map(composition.map((r) => [r.symbol.toUpperCase(), r]));

  const rows = targets.map((t) => {
    const row = bySymbol.get(t.asset);
    const valueUsd = row ? row.amount * row.price : 0;
    const currentPct = totalValue > 0 ? (valueUsd / totalValue) * 100 : 0;
    const drift = currentPct - t.allocation;
    // Bands are asymmetric on purpose: an asset may be allowed to run above
    // target further than it is allowed to fall below, or vice versa.
    const outOfBand = !isEmpty && (drift > t.upperThreshold || drift < -t.lowerThreshold);
    return {
      asset: t.asset,
      targetPct: t.allocation,
      currentPct: Math.round(currentPct * 10000) / 10000,
      driftPct: Math.round(drift * 10000) / 10000,
      valueUsd: Math.round(valueUsd * 100) / 100,
      targetUsd: Math.round(totalValue * (t.allocation / 100) * 100) / 100,
      lowerThreshold: t.lowerThreshold,
      upperThreshold: t.upperThreshold,
      slippage: t.slippage,
      outOfBand,
      inVault: Boolean(row),
    };
  });

  // Value held in assets that are not part of the index at all. Surfaced
  // rather than silently ignored: it dilutes every weight, so a vault can
  // look permanently under-allocated without an obvious reason.
  const targetSymbols = new Set(targets.map((t) => t.asset));
  const unmanaged = composition
    .filter((r) => !targetSymbols.has(r.symbol.toUpperCase()) && r.amount * r.price > 0.01)
    .map((r) => ({
      asset: r.symbol,
      valueUsd: Math.round(r.amount * r.price * 100) / 100,
    }));

  return { totalValue: Math.round(totalValue * 100) / 100, isEmpty, rows, unmanaged };
}

/**
 * @openapi
 * /getCurrentAllocations:
 *   get:
 *     summary: Get target vs live allocations and drift for a vault
 *     description: >-
 *       Returns the stored targets together with each asset's current weight,
 *       its drift in percentage points, and whether it has left its tolerance
 *       band. Also reports any value held in assets outside the index, which
 *       dilutes every weight. Read-only.
 *     tags: [Allocations]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *     responses:
 *       200:
 *         description: Targets, live weights and drift.
 */
router.get('/getCurrentAllocations', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };
  const apiKey = String(q.apiKey || '');
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const pool = String(q.pool || '').toLowerCase();
  const network = String(q.network || '').toLowerCase();

  const check = await basicCheck({ network, protocol, pool, apiKey });
  if (check.status === 'fail') return res.json(toRWireFormat(check));

  try {
    const stored = await loadTargets(network, pool);
    if (!stored) {
      return res.json(fail(404, `No allocations configured for pool ${pool} on ${network}`));
    }

    const drift = await computeDrift(pool, network, protocol, apiKey, stored.targets);
    if (!drift) {
      // Targets are still useful even when composition is unavailable, so
      // return them rather than failing the whole call.
      return res.json({
        status: 'success',
        status_code: 200,
        message: 'Allocations found, but live composition is unavailable',
        data: { network, pool, targets: stored.targets, max_usd: stored.maxUsd, platform: stored.platform },
      });
    }

    return res.json({
      status: 'success',
      status_code: 200,
      data: {
        network,
        pool,
        platform: stored.platform,
        max_usd: stored.maxUsd,
        totalValueUsd: drift.totalValue,
        needsRebalance: drift.rows.some((r) => r.outOfBand),
        allocations: drift.rows,
        unmanagedAssets: drift.unmanaged,
      },
    });
  } catch (e: any) {
    console.log(`Error: getCurrentAllocations pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json(fail(500, 'Internal error reading allocations'));
  }
});

/**
 * @openapi
 * /rebalancePool:
 *   post:
 *     summary: Rebalance a vault back to its target index allocations
 *     description: >-
 *       Computes the trades needed to bring every asset back to its target
 *       weight and, when execute=true, runs them through /vaultTrade.
 *       DRY-RUN BY DEFAULT — call with execute=true to move funds. Only assets
 *       outside their tolerance band are traded unless force=true. Sells run
 *       before buys so the proceeds are available to fund the buys.
 *     tags: [Allocations]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *       - in: query
 *         name: execute
 *         description: Set true to actually submit the trades. Defaults to false (dry run).
 *         schema: { type: boolean, default: false }
 *       - in: query
 *         name: force
 *         description: Rebalance every asset, including those still inside their band.
 *         schema: { type: boolean, default: false }
 *       - in: query
 *         name: quote
 *         description: Asset used as the intermediary when selling and buying. Defaults to USDC.
 *         schema: { type: string, default: 'USDC' }
 *     responses:
 *       200:
 *         description: The rebalance plan, plus execution results when execute=true.
 */
router.post('/rebalancePool', async (req: Request, res: Response) => {
  const q = { ...req.query, ...req.body };

  // Money-moving when execute=true, so it takes the full trader-verified
  // chain regardless of mode; a dry run should not be more permissive than
  // the thing it previews.
  const auth = await requireLendingAuth(req);
  if (!auth.ok) return res.json(auth.body);
  const { apiKey, protocol, pool, network } = auth;

  const execute = String(q.execute ?? 'false').toLowerCase() === 'true';
  const force = String(q.force ?? 'false').toLowerCase() === 'true';
  const quote = String(q.quote || 'USDC').toUpperCase();

  try {
    const stored = await loadTargets(network, pool);
    if (!stored) {
      return res.json(fail(404, `No allocations configured for pool ${pool} on ${network}`));
    }

    const drift = await computeDrift(pool, network, protocol, apiKey, stored.targets);
    if (!drift) return res.json(fail(400, 'unable to fetch pool composition'));

    // force still cannot rebalance an empty vault: there is nothing to sell
    // and no funds to buy with.
    const candidates = drift.isEmpty ? [] : drift.rows.filter((r) => (force ? true : r.outOfBand));

    // A trade is only worth making if it is large enough to matter after
    // slippage and gas; sub-dollar dust would otherwise churn the vault.
    const MIN_TRADE_USD = 1;
    const plan = candidates
      .map((r) => {
        const deltaUsd = r.targetUsd - r.valueUsd;
        return {
          asset: r.asset,
          side: deltaUsd > 0 ? ('buy' as const) : ('sell' as const),
          amountUsd: Math.abs(Math.round(deltaUsd * 100) / 100),
          from: deltaUsd > 0 ? quote : r.asset,
          to: deltaUsd > 0 ? r.asset : quote,
          slippage: r.slippage,
          currentPct: r.currentPct,
          targetPct: r.targetPct,
        };
      })
      // Drop self-trades. When the quote asset is itself an index target its
      // weight is satisfied as the residual of the other legs -- the sells
      // deliver the quote and the buys spend it -- so an explicit
      // quote->quote leg is a no-op that would still cost gas and slippage.
      .filter((p) => p.from !== p.to)
      .filter((p) => p.amountUsd >= MIN_TRADE_USD);

    if (stored.maxUsd > 0) {
      const total = plan.reduce((s, p) => s + p.amountUsd, 0);
      if (total > stored.maxUsd) {
        return res.json(
          fail(
            400,
            `Rebalance would trade $${Math.round(total * 100) / 100}, exceeding the configured max_usd of $${stored.maxUsd}`
          )
        );
      }
    }

    // Sells first: they produce the quote asset that the buys spend.
    const ordered = [...plan.filter((p) => p.side === 'sell'), ...plan.filter((p) => p.side === 'buy')];

    if (!execute) {
      return res.json({
        status: 'success',
        status_code: 200,
        message:
          ordered.length === 0
            ? 'No rebalance needed — every asset is within its tolerance band'
            : `Dry run: ${ordered.length} trade(s) planned. Call again with execute=true to submit.`,
        data: {
          network,
          pool,
          executed: false,
          totalValueUsd: drift.totalValue,
          unmanagedAssets: drift.unmanaged,
          plan: ordered,
        },
      });
    }

    const results: any[] = [];
    for (const p of ordered) {
      const params = new URLSearchParams({
        apiKey,
        protocol,
        pool,
        network,
        from: p.from,
        to: p.to,
        amount: String(p.amountUsd),
        slippage: String(p.slippage),
        platform: stored.platform,
      });
      try {
        const resp = await fetch(`${EXPRESS_BASE}vaultTrade?${params.toString()}`, { method: 'POST' });
        const body: any = await resp.json().catch(() => ({}));
        const ok = body?.status === 'success' || body?.status?.[0] === 'success';
        results.push({ ...p, ok, response: body });
        // Stop on the first failure. Continuing would push the vault further
        // from target, and a failed sell means the following buys are unfunded.
        if (!ok) break;
      } catch (e: any) {
        results.push({ ...p, ok: false, response: e.message });
        break;
      }
    }

    const failed = results.filter((r) => !r.ok).length;
    return res.json({
      status: failed === 0 ? 'success' : 'fail',
      status_code: failed === 0 ? 200 : 500,
      message:
        failed === 0
          ? `Rebalanced: ${results.length} trade(s) executed`
          : `Rebalance stopped after a failed trade; ${results.length - failed} of ${ordered.length} completed`,
      data: { network, pool, executed: true, totalValueUsd: drift.totalValue, trades: results },
    });
  } catch (e: any) {
    console.log(`Error: rebalancePool pool: ${pool} network: ${network} error: ${e.message}`);
    return res.json(fail(500, `Internal error rebalancing: ${e.message}`));
  }
});

export default router;
