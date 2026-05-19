import { Dapp, Network, ethers } from "@dhedge/v2-sdk";
import { Router, Request, Response } from "express";
import { dhedgev2 } from "../dhedge";
import { getTxOptions } from "../utils/txOptions";
import { txFees, apiPayment } from "../txFees";
import { getTokenDecimals } from "../utils/ERC20";
import { tradeWithFallback } from "./trade-fallback";
import { parseDapp } from "../utils/parseDapp";

const liquidityRouter = Router();

// ─── Helpers ──────────────────────────────────────────────────────────────────

function sendErrorResponse(
    res: Response,
    statusCode: number,
    errorCode: number,
    message: string,
    errorType: string
) {
    res.status(statusCode).send({ status: "fail", status_code: errorCode, message, error_type: errorType });
}

/** Returns the on-chain balance of `asset` from composition, or BigNumber(0) if absent. */
function balanceOrZero(asset: string, composition: any[]): ethers.BigNumber {
    const entry = composition.find((x: any) => x.asset.toLowerCase() === asset.toLowerCase());
    if (!entry || !entry.balance) return ethers.BigNumber.from(0);
    return entry.balance;
}

/**
 * Validate that `raw` is a checksummed-or-lower-case EVM address.
 * Throws a descriptive error on failure — never passes arbitrary input through.
 */
function requireAddress(raw: string | undefined, label: string): string {
    if (!raw || !raw.trim()) throw new Error(`${label} is required`);
    const addr = raw.trim();
    if (!ethers.utils.isAddress(addr)) throw new Error(`${label} must be a valid Ethereum address: ${addr}`);
    return addr.toLowerCase();
}

/** Parse a price bound: null = full-range side */
function parsePriceBound(raw: string | undefined): number | null {
    if (!raw || raw.trim() === "" || raw.trim().toLowerCase() === "null") return null;
    const n = parseFloat(raw.trim());
    if (!Number.isFinite(n) || n < 0) throw new Error(`Invalid price bound: ${raw}`);
    return n;
}

const SUPPORTED_LP_PLATFORMS = new Set(["uniswapv3"]);
const VALID_FEE_TIERS = new Set([500, 3000, 10000]);

// ─── POST /addLiquidity ───────────────────────────────────────────────────────
/**
 * Add UniswapV3 liquidity to a dHEDGE vault.
 *
 * Parameters (all via query string):
 *   network        - chain (e.g. "base")
 *   pool           - vault address
 *   apiKey         - dHEDGE API key
 *   asset1         - token A of the pair
 *   asset2         - token B of the pair
 *   input_asset    - source token; if != asset1/asset2 it will be swapped 50/50
 *   platform       - "uniswapv3" (default; only supported value)
 *   fee_tier       - 500 | 3000 | 10000 (default 3000)
 *   lower_price    - lower price bound; omit / "null" = full-range
 *   upper_price    - upper price bound; omit / "null" = full-range
 *   share          - % of input_asset balance to use (0-100, default 100)
 *   amount         - explicit token amount (overrides share)
 *   slippage       - swap slippage % (default 0.5)
 *   provider       - RPC provider name (optional)
 *   providerKey    - RPC provider key (optional)
 */
liquidityRouter.post("/addLiquidity", async (req: Request, res: Response) => {
    try {
        // ── 1. Parse & validate all inputs ────────────────────────────────────
        const network = (req.query.network as string | undefined)?.trim().toLowerCase() as Network;
        if (!network) throw new Error("network is required");

        const rawPlatform = ((req.query.platform as string | undefined) ?? "uniswapv3").trim().toLowerCase();
        if (!SUPPORTED_LP_PLATFORMS.has(rawPlatform))
            throw new Error(`Unsupported platform: ${rawPlatform}. Supported: uniswapv3`);

        const poolAddress = (req.query.pool as string | undefined)?.trim();
        if (!poolAddress) throw new Error("pool is required");
        if (!ethers.utils.isAddress(poolAddress)) throw new Error("pool must be a valid Ethereum address");

        const apiKey = (req.query.apiKey as string | undefined)?.trim();
        if (!apiKey) throw new Error("apiKey is required");

        const asset1 = requireAddress(req.query.asset1 as string | undefined, "asset1");
        const asset2 = requireAddress(req.query.asset2 as string | undefined, "asset2");
        if (asset1 === asset2) throw new Error("asset1 and asset2 must be different tokens");

        const inputAsset = requireAddress(req.query.input_asset as string | undefined, "input_asset");

        // fee_tier: whitelist only
        const feeTierRaw = (req.query.fee_tier as string | undefined)?.trim();
        const feeTier = feeTierRaw ? parseInt(feeTierRaw, 10) : 3000;
        if (!Number.isInteger(feeTier) || !VALID_FEE_TIERS.has(feeTier))
            throw new Error("fee_tier must be one of: 500, 3000, 10000");

        // Price bounds (null = full range)
        const lowerPrice = parsePriceBound(req.query.lower_price as string | undefined);
        const upperPrice = parsePriceBound(req.query.upper_price as string | undefined);
        if (lowerPrice !== null && upperPrice !== null && lowerPrice >= upperPrice)
            throw new Error("lower_price must be strictly less than upper_price");

        // Slippage bounded to prevent accidental large values
        const slippage = parseFloat((req.query.slippage as string | undefined) ?? "0.5");
        if (!Number.isFinite(slippage) || slippage <= 0 || slippage > 50)
            throw new Error("slippage must be in (0, 50]");

        const provider = (req.query.provider as string | undefined) ?? null;
        const key = (req.query.providerKey as string | undefined) ?? null;

        // ── 2. Load pool ───────────────────────────────────────────────────────
        const dapp = parseDapp(rawPlatform) as Dapp.UNISWAPV3 | Dapp.VELODROMECL | Dapp.AERODROMECL | Dapp.PANCAKECL;
        const dHedge = await dhedgev2(network, apiKey, provider, key);
        const pool = await dHedge.loadPool(poolAddress);

        // ── 3. Validate input_asset has balance ────────────────────────────────
        const composition = await pool.getComposition();
        const inputBalance = balanceOrZero(inputAsset, composition);
        if (inputBalance.isZero())
            throw new Error(`input_asset ${inputAsset} has zero balance in vault`);

        // ── 4. Compute amount to use ───────────────────────────────────────────
        let inputAmount: ethers.BigNumber;
        const amountRaw = (req.query.amount as string | undefined)?.trim();
        const shareRaw = (req.query.share as string | undefined)?.trim();

        if (amountRaw && amountRaw !== "") {
            if (!/^\d+(\.\d+)?$/.test(amountRaw))
                throw new Error("amount must be a non-negative decimal number");
            const decimals = await getTokenDecimals(inputAsset, network, provider, key);
            inputAmount = ethers.utils.parseUnits(amountRaw, decimals);
            if (inputAmount.gt(inputBalance))
                throw new Error("amount exceeds available vault balance");
        } else {
            const share = parseFloat(shareRaw ?? "100");
            if (!Number.isFinite(share) || share <= 0 || share > 100)
                throw new Error("share must be in (0, 100]");
            // Use bps arithmetic to avoid floating-point rounding
            inputAmount = inputBalance.mul(Math.round(share * 100)).div(10000);
        }

        if (inputAmount.isZero()) throw new Error("Computed input amount is zero");

        // ── 5. Swap input_asset → asset1 and/or asset2 ────────────────────────
        //      Strategy: 50/50 split by token amount.
        //      If input == asset1: keep half, swap half → asset2
        //      If input == asset2: keep half, swap half → asset1
        //      If input is neither: swap 50% → asset1, swap 50% → asset2
        const isInputAsset1 = inputAsset === asset1;
        const isInputAsset2 = inputAsset === asset2;

        if (!isInputAsset1 && !isInputAsset2) {
            const half = inputAmount.div(2);
            console.log(`/addLiquidity: swapping input → asset1 (${asset1}), amount=${half}`);
            await tradeWithFallback({
                pool, network, primaryDapp: Dapp.ODOS,
                assetFrom: inputAsset, assetTo: asset1,
                amountIn: half, slippage,
                txOptions: await getTxOptions(network, provider, key),
                estimateGasOnly: false
            });
            console.log(`/addLiquidity: swapping input → asset2 (${asset2}), amount=${inputAmount.sub(half)}`);
            await tradeWithFallback({
                pool, network, primaryDapp: Dapp.ODOS,
                assetFrom: inputAsset, assetTo: asset2,
                amountIn: inputAmount.sub(half), slippage,
                txOptions: await getTxOptions(network, provider, key),
                estimateGasOnly: false
            });
        } else if (isInputAsset1) {
            const half = inputAmount.div(2);
            console.log(`/addLiquidity: swapping asset1 → asset2, amount=${half}`);
            await tradeWithFallback({
                pool, network, primaryDapp: Dapp.ODOS,
                assetFrom: asset1, assetTo: asset2,
                amountIn: half, slippage,
                txOptions: await getTxOptions(network, provider, key),
                estimateGasOnly: false
            });
        } else {
            // isInputAsset2
            const half = inputAmount.div(2);
            console.log(`/addLiquidity: swapping asset2 → asset1, amount=${half}`);
            await tradeWithFallback({
                pool, network, primaryDapp: Dapp.ODOS,
                assetFrom: asset2, assetTo: asset1,
                amountIn: half, slippage,
                txOptions: await getTxOptions(network, provider, key),
                estimateGasOnly: false
            });
        }

        // ── 6. Approve asset1 and asset2 for the UniswapV3 position manager ────
        //      This also implicitly verifies that the vault's UniswapV3 guard is active.
        console.log(`/addLiquidity: approving ${asset1} for UniswapV3 position manager...`);
        const txOptsA = await getTxOptions(network, provider, key);
        const estA = await pool.approveUniswapV3Liquidity(asset1, ethers.constants.MaxUint256, txOptsA, { estimateGas: true });
        await pool.approveUniswapV3Liquidity(asset1, ethers.constants.MaxUint256, await txFees(network, provider, key, estA));

        console.log(`/addLiquidity: approving ${asset2} for UniswapV3 position manager...`);
        const txOptsB = await getTxOptions(network, provider, key);
        const estB = await pool.approveUniswapV3Liquidity(asset2, ethers.constants.MaxUint256, txOptsB, { estimateGas: true });
        await pool.approveUniswapV3Liquidity(asset2, ethers.constants.MaxUint256, await txFees(network, provider, key, estB));

        // ── 7. Use fresh balances after swaps ─────────────────────────────────
        const freshComp = await pool.getComposition();
        const amountA = balanceOrZero(asset1, freshComp);
        const amountB = balanceOrZero(asset2, freshComp);
        if (amountA.isZero() && amountB.isZero())
            throw new Error("Both asset1 and asset2 have zero balance after swaps — nothing to provide");

        // ── 8. Add liquidity ───────────────────────────────────────────────────
        const rangeDesc = (lowerPrice === null && upperPrice === null)
            ? "full range"
            : `[${lowerPrice ?? "min"}, ${upperPrice ?? "max"}]`;
        console.log(`/addLiquidity: addLiquidityUniswapV3 fee=${feeTier} range=${rangeDesc} amountA=${amountA} amountB=${amountB}`);

        const txOptsLiq = await getTxOptions(network, provider, key);
        const estLiq = await pool.addLiquidityUniswapV3(
            dapp as Dapp.UNISWAPV3 | Dapp.VELODROMECL | Dapp.AERODROMECL | Dapp.PANCAKECL,
            asset1, asset2, amountA, amountB,
            lowerPrice, upperPrice,
            null, null, // ticks — calculated from prices by the SDK
            feeTier,
            txOptsLiq, { estimateGas: true }
        );
        const tx = await pool.addLiquidityUniswapV3(
            dapp as Dapp.UNISWAPV3 | Dapp.VELODROMECL | Dapp.AERODROMECL | Dapp.PANCAKECL,
            asset1, asset2, amountA, amountB,
            lowerPrice, upperPrice,
            null, null,
            feeTier,
            await txFees(network, provider, key, estLiq)
        );

        console.log(`/addLiquidity: success tx=${tx.hash}`);
        if (apiKey) apiPayment(network, apiKey, tx, provider, key, null);
        res.status(200).send({ status: "success", msg: tx.hash });
    } catch (err) {
        const message = (err instanceof Error) ? err.message : String(err);
        console.error(`❌ /addLiquidity failed: ${message.substring(0, 250)}`);
        sendErrorResponse(res, 400, 6001, message, "add_liquidity_failed");
    }
});

// ─── POST /removeLiquidity ────────────────────────────────────────────────────
/**
 * Remove liquidity from a UniswapV3 position held by a dHEDGE vault.
 *
 * Parameters (all via query string):
 *   network        - chain
 *   pool           - vault address
 *   apiKey         - dHEDGE API key
 *   asset1         - token A of the pair
 *   asset2         - token B of the pair
 *   token_id       - UniswapV3 NFT position ID (uint256 string)
 *   platform       - "uniswapv3" (default)
 *   amount         - % of liquidity to remove (0-100, default 100)
 *   output_asset   - "both" (default) | asset1 addr | asset2 addr | other addr
 *                    "both"    → keep both tokens in vault
 *                    asset1    → swap asset2 proceeds → asset1
 *                    asset2    → swap asset1 proceeds → asset2
 *                    other     → swap both proceeds → that token
 *   slippage       - swap slippage % (default 0.5)
 *   provider       - RPC provider name (optional)
 *   providerKey    - RPC provider key (optional)
 */
liquidityRouter.post("/removeLiquidity", async (req: Request, res: Response) => {
    try {
        // ── 1. Parse & validate all inputs ────────────────────────────────────
        const network = (req.query.network as string | undefined)?.trim().toLowerCase() as Network;
        if (!network) throw new Error("network is required");

        const rawPlatform = ((req.query.platform as string | undefined) ?? "uniswapv3").trim().toLowerCase();
        if (!SUPPORTED_LP_PLATFORMS.has(rawPlatform))
            throw new Error(`Unsupported platform: ${rawPlatform}. Supported: uniswapv3`);

        const poolAddress = (req.query.pool as string | undefined)?.trim();
        if (!poolAddress) throw new Error("pool is required");
        if (!ethers.utils.isAddress(poolAddress)) throw new Error("pool must be a valid Ethereum address");

        const apiKey = (req.query.apiKey as string | undefined)?.trim();
        if (!apiKey) throw new Error("apiKey is required");

        const asset1 = requireAddress(req.query.asset1 as string | undefined, "asset1");
        const asset2 = requireAddress(req.query.asset2 as string | undefined, "asset2");
        if (asset1 === asset2) throw new Error("asset1 and asset2 must be different");

        // token_id: NFT position ID — must be a non-negative integer string
        const tokenIdRaw = (req.query.token_id as string | undefined)?.trim();
        if (!tokenIdRaw) throw new Error("token_id is required");
        if (!/^\d+$/.test(tokenIdRaw))
            throw new Error("token_id must be a non-negative integer string (e.g. '123456')");

        // amount: percentage of liquidity to remove (default 100%)
        const removeAmount = parseFloat((req.query.amount as string | undefined) ?? "100");
        if (!Number.isFinite(removeAmount) || removeAmount <= 0 || removeAmount > 100)
            throw new Error("amount must be a percentage in (0, 100]");

        // output_asset: "both", asset1, asset2, or another tracked token address
        const outputAssetRaw = ((req.query.output_asset as string | undefined) ?? "both").trim();
        let outputAsset: string | "both";
        if (outputAssetRaw.toLowerCase() === "both") {
            outputAsset = "both";
        } else {
            outputAsset = requireAddress(outputAssetRaw, "output_asset");
        }

        const slippage = parseFloat((req.query.slippage as string | undefined) ?? "0.5");
        if (!Number.isFinite(slippage) || slippage <= 0 || slippage > 50)
            throw new Error("slippage must be in (0, 50]");

        const provider = (req.query.provider as string | undefined) ?? null;
        const key = (req.query.providerKey as string | undefined) ?? null;

        // ── 2. Load pool ───────────────────────────────────────────────────────
        const dapp = parseDapp(rawPlatform);
        const dHedge = await dhedgev2(network, apiKey, provider, key);
        const pool = await dHedge.loadPool(poolAddress);

        // ── 3. Validate output_asset is in vault composition (if not asset1/2) ─
        if (outputAsset !== "both" && outputAsset !== asset1 && outputAsset !== asset2) {
            const comp = await pool.getComposition();
            const tracked = comp.map((x: any) => x.asset.toLowerCase());
            if (!tracked.includes(outputAsset))
                throw new Error(`output_asset ${outputAsset} is not tracked in vault composition`);
        }

        // ── 4. Decrease liquidity ──────────────────────────────────────────────
        console.log(`/removeLiquidity: decreaseLiquidity tokenId=${tokenIdRaw} amount=${removeAmount}%`);
        const txOptsBase = await getTxOptions(network, provider, key);
        const estRemove = await pool.decreaseLiquidity(dapp, tokenIdRaw, removeAmount, txOptsBase, { estimateGas: true });
        const tx = await pool.decreaseLiquidity(dapp, tokenIdRaw, removeAmount, await txFees(network, provider, key, estRemove));
        console.log(`/removeLiquidity: tx submitted: ${tx.hash}`);
        if (apiKey) apiPayment(network, apiKey, tx, provider, key, null);

        // ── 5. Optionally swap proceeds to output_asset ────────────────────────
        if (outputAsset !== "both") {
            // Wait for confirmation before reading updated balances
            await tx.wait(1);
            const freshComp = await pool.getComposition();

            if (outputAsset === asset1) {
                // Keep asset1; swap asset2 → asset1
                const bal2 = balanceOrZero(asset2, freshComp);
                if (!bal2.isZero()) {
                    console.log(`/removeLiquidity: swapping asset2 → asset1 (${asset1})`);
                    await tradeWithFallback({
                        pool, network, primaryDapp: Dapp.ODOS,
                        assetFrom: asset2, assetTo: outputAsset,
                        amountIn: bal2, slippage,
                        txOptions: await getTxOptions(network, provider, key),
                        estimateGasOnly: false
                    });
                }
            } else if (outputAsset === asset2) {
                // Keep asset2; swap asset1 → asset2
                const bal1 = balanceOrZero(asset1, freshComp);
                if (!bal1.isZero()) {
                    console.log(`/removeLiquidity: swapping asset1 → asset2 (${asset2})`);
                    await tradeWithFallback({
                        pool, network, primaryDapp: Dapp.ODOS,
                        assetFrom: asset1, assetTo: outputAsset,
                        amountIn: bal1, slippage,
                        txOptions: await getTxOptions(network, provider, key),
                        estimateGasOnly: false
                    });
                }
            } else {
                // Swap both asset1 and asset2 → outputAsset
                const bal1 = balanceOrZero(asset1, freshComp);
                const bal2 = balanceOrZero(asset2, freshComp);
                if (!bal1.isZero()) {
                    console.log(`/removeLiquidity: swapping asset1 → ${outputAsset}`);
                    await tradeWithFallback({
                        pool, network, primaryDapp: Dapp.ODOS,
                        assetFrom: asset1, assetTo: outputAsset,
                        amountIn: bal1, slippage,
                        txOptions: await getTxOptions(network, provider, key),
                        estimateGasOnly: false
                    });
                }
                if (!bal2.isZero()) {
                    console.log(`/removeLiquidity: swapping asset2 → ${outputAsset}`);
                    await tradeWithFallback({
                        pool, network, primaryDapp: Dapp.ODOS,
                        assetFrom: asset2, assetTo: outputAsset,
                        amountIn: bal2, slippage,
                        txOptions: await getTxOptions(network, provider, key),
                        estimateGasOnly: false
                    });
                }
            }
        }

        res.status(200).send({ status: "success", msg: tx.hash });
    } catch (err) {
        const message = (err instanceof Error) ? err.message : String(err);
        console.error(`❌ /removeLiquidity failed: ${message.substring(0, 250)}`);
        sendErrorResponse(res, 400, 6002, message, "remove_liquidity_failed");
    }
});

export default liquidityRouter;
