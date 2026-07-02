import { Dapp, ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { BigNumber } from "ethers"
import { Request, Response } from "express";
import { getBalanceFromComposition } from "../utils/pool";
import { getTxOptions } from "../utils/txOptions";
import { dhedge, dhedgev2 } from "../dhedge";
import { wallet } from "../wallet";
import { walletv2 } from "../walletv2";
import { apiPayment, feeData, txFees } from "../txFees";
import { rpc } from "../rpc";
import { getPoolAaveData, getAaveV3HealthFactor, getSupplied, getBorrowed } from "../utils/AAVE";
import { getTokenDecimals } from "../utils/ERC20";

// Error response helper
function sendErrorResponse(res: Response, statusCode: number, errorCode: number, message: string, errorType: string, details?: any) {
  const response: any = {
    status: "fail",
    status_code: errorCode,
    message: message,
    error_type: errorType
  };
  if (details) {
    response.details = details;
  }
  res.status(statusCode).send(response);
}

/**
 * Pre-flight simulation guard: throws if the SDK gas estimation returned a
 * gasEstimationError object (meaning the TX would revert on-chain).
 * Call this immediately after every pool.lend / pool.withdrawDeposit /
 * pool.lendCompoundV3 / pool.withdrawCompoundV3 / pool.approveSpender call
 * made with the estimateGas=true flag, BEFORE submitting the real TX.
 *
 * Distinguishes EVM reverts ("TX will revert") from JS/infrastructure errors
 * (network timeouts, frozen objects, etc.) so callers see an accurate message.
 */
function assertGasEstimationOk(estimatedGas: any, operation: string): void {
  if (estimatedGas && typeof estimatedGas === 'object' && estimatedGas.gasEstimationError) {
    const gasError = estimatedGas.gasEstimationError;
    const detail = gasError?.message || gasError?.reason || String(gasError);
    const lower = detail.toLowerCase();
    // Positive EVM-revert detection — if the error (or its nested reason) contains
    // a known revert marker, the TX will fail on-chain → block it.
    // Everything else is a JS/network/infrastructure error → let caller retry.
    const isEvmRevert =
      lower.includes('execution reverted') ||
      lower.includes('transaction reverted') ||
      lower.includes('call_exception');
    if (isEvmRevert) {
      throw new Error(`TX will revert — not executed (${operation}): ${detail.substring(0, 300)}`);
    }
    throw new Error(`Simulation infrastructure error (${operation}): ${detail.substring(0, 300)}`);
  }
}

function toBigAmount(amountDecStr: string, decimals: number): ethers.BigNumber {
  const s = amountDecStr.trim();
  if (!/^\d+(\.\d+)?$/.test(s)) throw new Error("amount must be a decimal string");
  return ethers.utils.parseUnits(s, decimals);
}
// percent (0–100, up to 2 dp) to bps (0–10000)
function percentToBps(percentStr: string): number {
  const n = Number(percentStr);
  if (!isFinite(n)) throw new Error("share must be numeric");
  if (n <= 0 || n > 100) throw new Error("share must be in (0,100]");
  return Math.round(n * 100); // 12.34% -> 1234 bps
}

// ── Input validation helpers ──────────────────────────────────────────────────
// Network validation is handled by the API gateway (basic_check uses the DB
// cache). Express only validates Ethereum address format, since it is called
// from localhost (by strategies and the gateway) — not exposed to the internet.

/** Throws if value is not a valid 0x Ethereum address. Returns the lowercased address. */
function assertAddress(value: string | undefined, name: string): string {
  if (!value || !ethers.utils.isAddress(value)) {
    throw new Error(`Invalid Ethereum address for param '${name}': ${value}`);
  }
  return value.toLowerCase();
}

// Aave V3 pool contract addresses by network — used for auto-approve on allowance errors
const AAVE_V3_POOLS: Record<string, string> = {
  "mainnet": "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
  "polygon": "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  "base": "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
  "optimism": "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  "arbitrum": "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
};

const lendingRouter = Router();

lendingRouter.post("/borrow", async (req: Request, res: Response) => {
  try {
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    const asset = req.query.asset as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    const poolAddress = req.query.pool as string;
    let pool; let provider = null; let key = null;
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    let apiKey = null;
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge = await dhedgev2(network, apiKey, provider, key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    let amount: ethers.BigNumber;
    //const composition = await pool.getComposition();
    //const balance = getBalanceFromComposition(asset,composition);

    //if (req.query.share) {
    //        const share = req.query.share as string;
    //        amount = balance.mul(share).div(100);
    //}

    if (req.query.amount) {
      const string_amount = req.query.amount as string;
      amount = ethers.BigNumber.from(string_amount);
      //if (amount.gt(balance)) amount === balance;
    }

    else throw "share or amount parameters missing";

    const txOptions = await getTxOptions(pool.network, provider, key);
    let tx; let dApp: Dapp;

    if (req.query.platform) {
      const platform = (req.query.platform as string).toLowerCase();
      if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
      else throw "Unsupported lending/borrowing protocol";
    }

    else throw "platform parameter missing"

    let estimatedGas = null
    estimatedGas = await pool.borrow(dApp, asset, amount, 0, txOptions, true);
    console.log("estimated gas for repay tx")
    console.log(estimatedGas)
    assertGasEstimationOk(estimatedGas, "/borrow");
    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    tx = await pool.borrow(dApp, asset, amount, 0, txOptions2, false);
    console.log("repay transaction:")
    console.log(tx)
    if (apiKey) { console.log("Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null) }

    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 5001, message, "borrow_failed");
  }
});

lendingRouter.post("/repay", async (req: Request, res: Response) => {
  try {
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    const asset = req.query.asset as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    const poolAddress = req.query.pool as string;
    let pool; let provider = null; let key = null;
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    let apiKey = null;
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge = await dhedgev2(network, apiKey, provider, key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    let amount: ethers.BigNumber;
    const composition = await pool.getComposition();
    const balance = getBalanceFromComposition(asset, composition);
    if (req.query.share) {
      const share = req.query.share as string;
      amount = balance.mul(share).div(100);
    }
    else if (req.query.amount) {
      const string_amount = req.query.amount as string;
      amount = ethers.BigNumber.from(string_amount);
      if (amount.gt(balance)) amount = balance;
    }
    else throw "share or amount parameters missing";

    const txOptions = await getTxOptions(pool.network, provider, key);
    let tx; let dApp: Dapp;

    if (req.query.platform) {
      const platform = (req.query.platform as string).toLowerCase();
      if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
      else if (platform == "compound") dApp = "compoundv3" as Dapp;
      else throw "Unsupported lending/borrowing protocol";
    }
    else throw "platform parameter missing"

    let estimatedGas = null
    estimatedGas = await pool.repay(dApp, asset, amount, txOptions, true);
    console.log("estimated gas for repay tx")
    console.log(estimatedGas)
    assertGasEstimationOk(estimatedGas, "/repay");
    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    tx = await pool.repay(dApp, asset, amount, txOptions2, false);
    console.log("repay transaction:")
    console.log(tx)
    if (apiKey) { console.log("Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null) }

    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 5002, message, "repay_failed");
  }
});

lendingRouter.post("/lend", async (req: Request, res: Response) => {
  try {
    console.log("/lend: endpoint invoked")
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw new Error("/lend: Network parameter missing");
    let dApp: Dapp;
    if (req.query.platform) {
      const platform = (req.query.platform as string).toLowerCase();
      if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
      else throw new Error("/lend: Unsupported platform");
    }
    else throw new Error("/lend: platform parameter missing")
    const asset = req.query.asset as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    const poolAddress = req.query.pool as string;
    let pool; let provider = null; let key = null;
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    let apiKey = null; let share = null
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge = await dhedgev2(network, apiKey, provider, key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    let lendAmount: ethers.BigNumber; let amount: ethers.BigNumber;
    console.log("/lend: fetching pool composition")
    const composition = await pool.getComposition();
    //console.log("one composition entry:", composition[0]);
    const balance = getBalanceFromComposition(asset, composition);
    console.log("/lend: [rpc] network/provider/key", { network, provider, key });
    const decimals = await getTokenDecimals(asset, network, provider, key);
    if (req.query.share != null) {
      const shareStr = String(req.query.share);
      const shareNum = Number.parseFloat(shareStr);
      if (!Number.isFinite(shareNum)) { throw new Error("/lend: invalid share"); }
      lendAmount = balance.mul(Math.floor(shareNum)).div(100);
    } else if (req.query.amount != null) {
      const decStr = String(req.query.amount);
      amount = toBigAmount(decStr, decimals);
      lendAmount = amount;
    } else {
      throw new Error("/lend: share or amount parameters missing");
    }
    const txOptions = await getTxOptions(pool.network, provider, key);
    console.log("/lend: tx Options to use:");
    console.log(txOptions);

    // guard: skip if nothing to lend
    if (lendAmount.isZero()) {
      console.log("/lend: lendAmount is zero — skipping tx");
      return res.status(200).send({ status: "skipped", msg: "zero balance, nothing to lend" });
    }

    // estimate gas (pre-flight simulation)
    console.log("/lend: estimated gas for the tx");
    let estimatedGas = await pool.lend(dApp, asset, lendAmount, 0, txOptions, true);
    console.log(estimatedGas);

    // If simulation returned gasEstimationError, detect cause and auto-fix if possible
    if (estimatedGas && typeof estimatedGas === 'object' && (estimatedGas as any).gasEstimationError) {
      const gasError = (estimatedGas as any).gasEstimationError;
      const errMsg = (gasError?.message || gasError?.reason || String(gasError)).toLowerCase();
      console.error(`/lend: simulation failed — ${errMsg.substring(0, 200)}`);

      // Positive EVM-revert detection — block only confirmed on-chain failures.
      // Everything else (JS errors, network timeouts, RPC server errors) is treated
      // as a transient infrastructure error so the strategy retries next cycle.
      const isEvmRevert =
        errMsg.includes('execution reverted') ||
        errMsg.includes('transaction reverted') ||
        errMsg.includes('call_exception');

      if (!isEvmRevert) {
        const detail = gasError?.message || gasError?.reason || String(gasError);
        throw new Error(`Lend simulation infrastructure error: ${String(detail).substring(0, 300)}`);
      }

      if (errMsg.includes('allowance') || errMsg.includes('approve') || errMsg.includes('transfer amount exceeds')) {
        // Auto-approve Aave V3 pool for this asset, then retry
        console.log('/lend: allowance issue detected — auto-approving Aave V3 pool');
        const aavePool = AAVE_V3_POOLS[network as string];
        if (!aavePool) throw new Error(`/lend: cannot auto-approve — no Aave V3 pool address for network ${network}`);
        const approveTxOptions = await getTxOptions(pool.network, provider, key);
        const approveEstGas = await pool.approveSpender(aavePool, asset, ethers.constants.MaxUint256, approveTxOptions, { estimateGas: true });
        assertGasEstimationOk(approveEstGas, '/lend approveSpender');
        const approveTxOptions2 = await txFees(network, provider, key, approveEstGas);
        const approveTx = await pool.approveSpender(aavePool, asset, ethers.constants.MaxUint256, approveTxOptions2, { estimateGas: false });
        console.log(`/lend: approval tx submitted: ${approveTx.hash}`);
        await approveTx.wait(1);
        // Retry estimate after approval
        estimatedGas = await pool.lend(dApp, asset, lendAmount, 0, txOptions, true);
        assertGasEstimationOk(estimatedGas, '/lend (retry after approve)');
        console.log('/lend: simulation passed after auto-approve');
      } else {
        const detail = gasError?.message || gasError?.reason || String(gasError);
        throw new Error(`TX will revert — not executed (/lend): ${String(detail).substring(0, 300)}`);
      }
    }

    // produce final overrides
    const txOptions2 = await txFees(network, provider, key, estimatedGas);

    // send tx
    console.log("/lend: transaction");
    const tx = await pool.lend(dApp, asset, lendAmount, 0, txOptions2, false);
    console.log(tx);
    if (apiKey) { console.log("/lend: Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null) }
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 5003, message, "lend_failed");
  }
});

lendingRouter.post("/unlend", async (req: Request, res: Response) => {
  try {
    console.log("/unlend: endpoint invoked")
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw new Error("/unlend: Network parameter missing");
    let dApp: Dapp;
    if (req.query.platform) {
      const platform = (req.query.platform as string).toLowerCase();
      if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
      else throw new Error("/unlend: Unsupported platform");
    }
    else throw new Error("/unlend: platform parameter missing")
    const asset = req.query.asset as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    const poolAddress = req.query.pool as string;
    let pool; let provider = null; let key = null;
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    let apiKey = null; let share = null
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge = await dhedgev2(network, apiKey, provider, key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    let unlendAmount: ethers.BigNumber; let amount: ethers.BigNumber;

    console.log("/unlend: [rpc] network/provider/key", { network, provider, key });
    const decimals = await getTokenDecimals(asset, network, provider, key);

    if (req.query.share != null) {
      // Get current supplied balance from AAVE using getSupplied
      const aaveContractAddress = req.query.contractAddress as string | undefined;
      if (!aaveContractAddress) {
        throw new Error("/unlend: contractAddress parameter required for share-based unlend");
      }
      const { suppliedAmount } = await getSupplied(poolAddress, asset, network, provider, key, aaveContractAddress);
      const suppliedBN = toBigAmount(suppliedAmount, decimals);

      const shareStr = String(req.query.share);
      const shareNum = Number.parseFloat(shareStr);
      if (!Number.isFinite(shareNum)) { throw new Error("/unlend: invalid share"); }

      unlendAmount = suppliedBN.mul(Math.floor(shareNum)).div(100);
      amount = unlendAmount;
      console.log(`/unlend: withdrawing ${shareNum}% of ${suppliedAmount} = ${ethers.utils.formatUnits(amount, decimals)}`);
    }
    else if (req.query.amount != null) {
      console.log("amount decimal in string")
      const decStr = String(req.query.amount);
      console.log(decStr)
      console.log("amount in big number")
      amount = toBigAmount(decStr, decimals);  // convert decimal -> BigNumber
      console.log(amount)
    }
    else { throw new Error("/unlend: share or amount parameters missing"); }

    const txOptions = await getTxOptions(pool.network, provider, key);
    console.log("/unlend: default tx Options to use:");
    console.log(txOptions);

    // estimate gas
    console.log("/unlend: estimated gas for the tx");
    const estimatedGas = await pool.withdrawDeposit(dApp, asset, amount, txOptions, true);
    console.log(estimatedGas);
    assertGasEstimationOk(estimatedGas, "/unlend");

    // produce final overrides
    const txOptions2 = await txFees(network, provider, key, estimatedGas);

    // send tx
    console.log("/unlend: executing withdrawDeposit tx");
    const tx = await pool.withdrawDeposit(dApp, asset, amount, txOptions2, false);
    console.log(tx);
    if (apiKey) { console.log("/unlend: Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null) }
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 5004, message, "unlend_failed");
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Fluid endpoints
//
// depositFluid  POST  ?network=base&pool=<vault>&asset=<underlying>&market=<fToken>
//                     &amount=<decimal>   OR   &share=<0-100>
//   asset   – underlying token to deposit (e.g. USDC on Base)
//   market  – fToken vault address (e.g. fUSDC 0xf42f…)
//   amount  – decimal string of underlying token units (overrides share)
//   share   – % of vault's current underlying balance to deposit
//
// withdrawFluid POST  ?network=base&pool=<vault>&asset=<underlying>&market=<fToken>
//                     &amount=<decimal>   OR   &share=<0-100>
//   amount  – decimal string of fToken units to redeem (overrides share)
//   share   – % of vault's current fToken balance to redeem
// ─────────────────────────────────────────────────────────────────────────────

// Known Fluid fToken markets: underlying → fToken
const FLUID_MARKETS: Record<string, string> = {
  // Base
  "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913": "0xf42f5795d9ac7e9d757db633d693cd548cfd9169", // USDC → fUSDC
};

lendingRouter.post("/depositFluid", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    console.log("[depositFluid] → request", req.query);

    // ── params (validated) ───────────────────────────────────────────────────
    const network = ((req.query.network as string | undefined) ?? "").toLowerCase() as Network;
    if (!network) throw new Error("network parameter missing");
    const poolAddress = assertAddress(req.query.pool as string | undefined, "pool");

    // asset = underlying token address (e.g. USDC)
    const asset = assertAddress(req.query.asset as string | undefined, "asset");

    // market = fToken address; derive automatically if not supplied
    let market = (req.query.market as string | undefined)?.toLowerCase();
    if (market) { market = assertAddress(market, "market"); }
    if (!market) {
      market = FLUID_MARKETS[asset];
      if (!market) throw new Error(`[depositFluid] no known fToken market for asset ${asset} — pass market= explicitly`);
    }

    const provider = (req.query.provider as string | undefined) ?? null;
    const key = (req.query.providerKey as string | undefined) ?? null;
    const apiKey = (req.query.apiKey as string | undefined) ?? null;
    const managerKey = (req.query.manager as string | undefined) ?? null;

    // ── load pool ────────────────────────────────────────────────────────────
    let pool: any;
    if (apiKey) {
      const d = await dhedgev2(network, apiKey, provider, key);
      pool = await d.loadPool(poolAddress);
    } else {
      pool = await dhedge(network, managerKey).loadPool(poolAddress);
    }

    // ── resolve amount ───────────────────────────────────────────────────────
    const decimals = await getTokenDecimals(asset, network, provider, key);
    let depositAmount: ethers.BigNumber;

    if (req.query.amount != null) {
      depositAmount = toBigAmount(String(req.query.amount), decimals);
      console.log(`[depositFluid] amount mode: ${req.query.amount} → ${depositAmount.toString()}`);
    } else if (req.query.share != null) {
      const composition = await pool.getComposition();
      const balance = getBalanceFromComposition(asset, composition);
      const shareNum = Number.parseFloat(String(req.query.share));
      if (!Number.isFinite(shareNum) || shareNum <= 0 || shareNum > 100)
        throw new Error("[depositFluid] share must be a number in (0, 100]");
      depositAmount = balance.mul(Math.floor(shareNum)).div(100);
      console.log(`[depositFluid] share mode: ${shareNum}% of ${balance.toString()} = ${depositAmount.toString()}`);
    } else {
      throw new Error("[depositFluid] amount or share parameter required");
    }

    if (depositAmount.lte(0)) {
      console.log("[depositFluid] depositAmount is 0 — skipping on-chain tx");
      return res.status(200).send({ status: "success", msg: "no_op_zero_amount" });
    }

    // ── Step 1: approve fToken market to spend the asset (skipApprove=true skips) ──
    const skipApprove = (req.query.skipApprove as string | undefined) === "true";
    if (skipApprove) {
      console.log(`[depositFluid] skipApprove=true — skipping allowance check`);
    } else {
      const assetContract = new ethers.Contract(asset, ["function allowance(address,address) view returns (uint256)"], pool.signer);
      const currentAllowance: ethers.BigNumber = await assetContract.allowance(pool.address, market);
      if (currentAllowance.lt(depositAmount)) {
        console.log(`[depositFluid] allowance ${currentAllowance.toString()} insufficient — approving MaxUint256`);
        const approveTxOptions = await getTxOptions(network, provider, key);
        const approveEstGas = await pool.approveSpender(market, asset, ethers.constants.MaxUint256, approveTxOptions, { estimateGas: true });
        assertGasEstimationOk(approveEstGas, "[depositFluid] approveSpender");
        const approveTxOptions2 = await txFees(network, provider, key, approveEstGas);
        const approveTx = await pool.approveSpender(market, asset, ethers.constants.MaxUint256, approveTxOptions2, { estimateGas: false });
        console.log(`[depositFluid] approve tx: ${approveTx.hash}`);
        await approveTx.wait(1);
      } else {
        console.log(`[depositFluid] allowance already sufficient — skipping approve`);
      }
    }

    // ── Step 2: deposit to Fluid fToken market ───────────────────────────────
    const txOptions = await getTxOptions(network, provider, key);
    const estimatedGas = await pool.lendCompoundV3(market, asset, depositAmount, txOptions, true);
    console.log("[depositFluid] estimatedGas:", estimatedGas);
    assertGasEstimationOk(estimatedGas, "[depositFluid] lendCompoundV3");

    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.lendCompoundV3(market, asset, depositAmount, txOptions2, false);
    console.log("[depositFluid] tx:", tx);

    if (apiKey) { console.log("[depositFluid] Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null); }

    console.log(`[depositFluid] ✓ success ms=${Date.now() - t0}`);
    return res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err: any) {
    const message = (err instanceof Error) ? err.message : String(err);
    console.log("[depositFluid] ! error", message);
    return sendErrorResponse(res, 400, 5010, message, "deposit_fluid_failed");
  }
});

lendingRouter.post("/withdrawFluid", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    console.log("[withdrawFluid] → request", req.query);

    // ── params (validated) ───────────────────────────────────────────────────
    const network = ((req.query.network as string | undefined) ?? "").toLowerCase() as Network;
    if (!network) throw new Error("network parameter missing");
    const poolAddress = assertAddress(req.query.pool as string | undefined, "pool");

    // asset = underlying token (needed by SDK withdrawCompoundV3)
    const asset = assertAddress(req.query.asset as string | undefined, "asset");

    // market = fToken address
    let market = (req.query.market as string | undefined)?.toLowerCase();
    if (market) { market = assertAddress(market, "market"); }
    if (!market) {
      market = FLUID_MARKETS[asset];
      if (!market) throw new Error(`[withdrawFluid] no known fToken market for asset ${asset} — pass market= explicitly`);
    }

    const provider = (req.query.provider as string | undefined) ?? null;
    const key = (req.query.providerKey as string | undefined) ?? null;
    const apiKey = (req.query.apiKey as string | undefined) ?? null;
    const managerKey = (req.query.manager as string | undefined) ?? null;

    // ── load pool ────────────────────────────────────────────────────────────
    let pool: any;
    if (apiKey) {
      const d = await dhedgev2(network, apiKey, provider, key);
      pool = await d.loadPool(poolAddress);
    } else {
      pool = await dhedge(network, managerKey).loadPool(poolAddress);
    }

    // ── resolve amount ───────────────────────────────────────────────────────
    // Withdrawal is denominated in fToken shares (what the vault holds)
    const fTokenDecimals = await getTokenDecimals(market, network, provider, key);
    let withdrawAmount: ethers.BigNumber;

    if (req.query.amount != null) {
      // amount expressed in underlying units — convert to fToken shares (1:1 for Fluid USDC)
      const underlyingDecimals = await getTokenDecimals(asset, network, provider, key);
      withdrawAmount = toBigAmount(String(req.query.amount), underlyingDecimals);
      console.log(`[withdrawFluid] amount mode: ${req.query.amount} → ${withdrawAmount.toString()}`);
    } else if (req.query.share != null) {
      // share of the vault's fToken balance
      const composition = await pool.getComposition();
      const fTokenBalance = getBalanceFromComposition(market, composition);
      const shareNum = Number.parseFloat(String(req.query.share));
      if (!Number.isFinite(shareNum) || shareNum <= 0 || shareNum > 100)
        throw new Error("[withdrawFluid] share must be a number in (0, 100]");
      withdrawAmount = fTokenBalance.mul(Math.floor(shareNum)).div(100);
      console.log(`[withdrawFluid] share mode: ${shareNum}% of ${fTokenBalance.toString()} = ${withdrawAmount.toString()}`);
    } else {
      throw new Error("[withdrawFluid] amount or share parameter required");
    }

    // ── estimate then send ───────────────────────────────────────────────────
    const txOptions = await getTxOptions(network, provider, key);
    const estimatedGas = await pool.withdrawCompoundV3(market, asset, withdrawAmount, txOptions, true);
    console.log("[withdrawFluid] estimatedGas:", estimatedGas);
    assertGasEstimationOk(estimatedGas, "[withdrawFluid] withdrawCompoundV3");

    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.withdrawCompoundV3(market, asset, withdrawAmount, txOptions2, false);
    console.log("[withdrawFluid] tx:", tx);

    if (apiKey) { console.log("[withdrawFluid] Sending API payment"); apiPayment(network, apiKey, tx, provider, key, null); }

    console.log(`[withdrawFluid] ✓ success ms=${Date.now() - t0}`);
    return res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err: any) {
    const message = (err instanceof Error) ? err.message : String(err);
    console.log("[withdrawFluid] ! error", message);
    return sendErrorResponse(res, 400, 5011, message, "withdraw_fluid_failed");
  }
});

lendingRouter.post("/depositCompoundV3", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    console.log("[depositCompoundV3] → request", req.query);

    // ── params (validated) ───────────────────────────────────────────────────
    const network = ((req.query.network as string | undefined) ?? "").toLowerCase() as Network;
    if (!network) throw new Error("network parameter missing");
    const poolAddress = assertAddress(req.query.pool as string | undefined, "pool");
    const asset = assertAddress(req.query.asset as string | undefined, "asset");

    // market = Comet address; auto-derive if not supplied
    let market = (req.query.market as string | undefined)?.toLowerCase();
    if (market) { market = assertAddress(market, "market"); }
    if (!market) {
      market = COMPOUND_V3_MARKETS[network.toLowerCase()]?.[asset];
      if (!market) throw new Error(`[depositCompoundV3] no known Comet market for asset ${asset} on ${network} — pass market= explicitly`);
    }

    const provider = (req.query.provider as string | undefined) ?? null;
    const key = (req.query.providerKey as string | undefined) ?? null;
    const apiKey = (req.query.apiKey as string | undefined) ?? null;
    const managerKey = (req.query.manager as string | undefined) ?? null;

    let pool: any;
    if (apiKey) { const d = await dhedgev2(network, apiKey, provider, key); pool = await d.loadPool(poolAddress); }
    else pool = await dhedge(network, managerKey).loadPool(poolAddress);

    const decimals = await getTokenDecimals(asset, network, provider, key);
    let depositAmount: ethers.BigNumber;

    if (req.query.amount != null) {
      depositAmount = toBigAmount(String(req.query.amount), decimals);
    } else if (req.query.share != null) {
      const composition = await pool.getComposition();
      const balance = getBalanceFromComposition(asset, composition);
      const shareNum = Number.parseFloat(String(req.query.share));
      if (!Number.isFinite(shareNum) || shareNum <= 0 || shareNum > 100)
        throw new Error("[depositCompoundV3] share must be in (0, 100]");
      depositAmount = balance.mul(Math.floor(shareNum)).div(100);
    } else {
      throw new Error("[depositCompoundV3] amount or share parameter required");
    }

    if (depositAmount.lte(0)) {
      console.log("[depositCompoundV3] depositAmount is 0 — skipping on-chain tx");
      return res.status(200).send({ status: "success", msg: "no_op_zero_amount" });
    }

    // Step 1: approve the Comet contract to spend the asset
    // skipApprove=true means the caller (strategy) has already cached a MaxUint256 approval
    const skipApprove = (req.query.skipApprove as string | undefined) === "true";
    if (skipApprove) {
      console.log(`[depositCompoundV3] skipApprove=true — skipping allowance check`);
    } else {
      const assetContract = new ethers.Contract(asset, ["function allowance(address,address) view returns (uint256)"], pool.signer);
      const currentAllowance: ethers.BigNumber = await assetContract.allowance(pool.address, market);
      if (currentAllowance.lt(depositAmount)) {
        console.log(`[depositCompoundV3] allowance ${currentAllowance.toString()} insufficient — approving MaxUint256`);
        const approveTxOptions = await getTxOptions(network, provider, key);
        const approveEstGas = await pool.approveSpender(market, asset, ethers.constants.MaxUint256, approveTxOptions, { estimateGas: true });
        assertGasEstimationOk(approveEstGas, "[depositCompoundV3] approveSpender");
        const approveTxOptions2 = await txFees(network, provider, key, approveEstGas);
        const approveTx = await pool.approveSpender(market, asset, ethers.constants.MaxUint256, approveTxOptions2, { estimateGas: false });
        console.log(`[depositCompoundV3] approve tx: ${approveTx.hash}`);
        await approveTx.wait(1);
      } else {
        console.log(`[depositCompoundV3] allowance already sufficient — skipping approve`);
      }
    }

    // Step 2: supply asset to Comet
    const txOptions = await getTxOptions(network, provider, key);
    const estimatedGas = await pool.lendCompoundV3(market, asset, depositAmount, txOptions, true);
    assertGasEstimationOk(estimatedGas, "[depositCompoundV3] lendCompoundV3");
    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.lendCompoundV3(market, asset, depositAmount, txOptions2, false);

    if (apiKey) { apiPayment(network, apiKey, tx, provider, key, null); }
    console.log(`[depositCompoundV3] ✓ success ms=${Date.now() - t0}`);
    return res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err: any) {
    const message = (err instanceof Error) ? err.message : String(err);
    console.log("[depositCompoundV3] ! error", message);
    return sendErrorResponse(res, 400, 5012, message, "deposit_compoundv3_failed");
  }
});

lendingRouter.post("/withdrawCompoundV3", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    console.log("[withdrawCompoundV3] → request", req.query);

    // ── params (validated) ───────────────────────────────────────────────────
    const network = ((req.query.network as string | undefined) ?? "").toLowerCase() as Network;
    if (!network) throw new Error("network parameter missing");
    const poolAddress = assertAddress(req.query.pool as string | undefined, "pool");
    const asset = assertAddress(req.query.asset as string | undefined, "asset");

    let market = (req.query.market as string | undefined)?.toLowerCase();
    if (market) { market = assertAddress(market, "market"); }
    if (!market) {
      market = COMPOUND_V3_MARKETS[network.toLowerCase()]?.[asset];
      if (!market) throw new Error(`[withdrawCompoundV3] no known Comet market for asset ${asset} on ${network} — pass market= explicitly`);
    }

    const provider = (req.query.provider as string | undefined) ?? null;
    const key = (req.query.providerKey as string | undefined) ?? null;
    const apiKey = (req.query.apiKey as string | undefined) ?? null;
    const managerKey = (req.query.manager as string | undefined) ?? null;

    let pool: any;
    if (apiKey) { const d = await dhedgev2(network, apiKey, provider, key); pool = await d.loadPool(poolAddress); }
    else pool = await dhedge(network, managerKey).loadPool(poolAddress);

    // Compound V3 withdrawal: denominated in underlying asset units
    const decimals = await getTokenDecimals(asset, network, provider, key);
    let withdrawAmount: ethers.BigNumber;

    if (req.query.amount != null) {
      withdrawAmount = toBigAmount(String(req.query.amount), decimals);
    } else if (req.query.share != null) {
      // share of the vault's cToken (Comet) balance
      const composition = await pool.getComposition();
      const cTokenBalance = getBalanceFromComposition(market, composition);
      const shareNum = Number.parseFloat(String(req.query.share));
      if (!Number.isFinite(shareNum) || shareNum <= 0 || shareNum > 100)
        throw new Error("[withdrawCompoundV3] share must be in (0, 100]");
      withdrawAmount = cTokenBalance.mul(Math.floor(shareNum)).div(100);
    } else {
      throw new Error("[withdrawCompoundV3] amount or share parameter required");
    }

    const txOptions = await getTxOptions(network, provider, key);
    const estimatedGas = await pool.withdrawCompoundV3(market, asset, withdrawAmount, txOptions, true);
    assertGasEstimationOk(estimatedGas, "[withdrawCompoundV3] withdrawCompoundV3");
    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.withdrawCompoundV3(market, asset, withdrawAmount, txOptions2, false);

    if (apiKey) { apiPayment(network, apiKey, tx, provider, key, null); }
    console.log(`[withdrawCompoundV3] ✓ success ms=${Date.now() - t0}`);
    return res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err: any) {
    const message = (err instanceof Error) ? err.message : String(err);
    console.log("[withdrawCompoundV3] ! error", message);
    return sendErrorResponse(res, 400, 5013, message, "withdraw_compoundv3_failed");
  }
});

lendingRouter.get("/getHealthFactor", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    // Parse
    type RpcNetwork = Parameters<typeof rpc>[0];
    const pool = req.query.pool as string | undefined;
    const network = req.query.network as RpcNetwork | undefined;
    const platform = (req.query.platform as string | undefined)?.toLowerCase();
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;
    const contractAddress = req.query.contractAddress as string | undefined;

    // Log request
    console.log("[HF] → request", {
      pool,
      network,
      platform,
      provider: provider ?? "(null)",
      providerKey: providerKey ? "***" : "(null)",
      contractAddress
    });

    // Validate
    if (!pool || !network || !platform || !contractAddress) {
      console.log("[HF] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, platform, contractAddress",
      });
    }
    if (platform !== "aave" && platform !== "aavev3") {
      console.log("[HF] ✖ unsupported platform:", platform);
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Unsupported platform",
      });
    }

    console.log("[HF] … computing health factor");
    const result = await getAaveV3HealthFactor(
      pool, network, provider, providerKey, contractAddress
    );

    // Support helper returning either number or { healthFactor }
    const healthFactor = typeof result === "number" ? result : (result as any).healthFactor;

    console.log("[HF] ✓ success", { healthFactor, ms: Date.now() - t0 });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      data: { healthFactor },
    });
  } catch (err: any) {
    console.log("[HF] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({
      status: "fail",
      status_code: 400,
      message: err?.message || String(err),
    });
  }
});
lendingRouter.get("/getPoolAaveData", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    // Parse
    type RpcNetworkFromHelper = Parameters<typeof rpc>[0]; // same trick as your HF route
    const pool = req.query.pool as string | undefined;
    const network = req.query.network as RpcNetworkFromHelper | undefined;
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;
    const contractAddress = req.query.contractAddress as string | undefined;

    // Log request
    console.log("[/getPoolAaveData] → request", {
      pool,
      network,
      provider: provider ?? "(null)",
      providerKey: providerKey ? "***" : "(null)",
      contractAddress
    });

    // Validate
    if (!pool || !network || !contractAddress) {
      console.log("[/getPoolAaveData] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, platform, contractAddress",
      });
    }
    console.log("[/getPoolAaveData] … fetching pool data");
    const { formatted } = await getPoolAaveData(
      pool, network, provider, providerKey, contractAddress
    );

    console.log("[/getPoolAaveData] ✓ success", { ms: Date.now() - t0, data: formatted });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "/getPoolAaveData invoked succesfully",
      data: formatted,
    });
  } catch (err: any) {
    console.log("[/getPoolAaveData] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({
      status: "fail",
      status_code: 400,
      message: err?.message || String(err),
    });
  }
});
lendingRouter.get("/getSupplied", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    // Parse
    type RpcNetworkFromHelper = Parameters<typeof rpc>[0]; // same trick as your HF route
    const pool = req.query.pool as string | undefined;
    const network = req.query.network as RpcNetworkFromHelper | undefined;
    const asset = req.query.asset as string | undefined;
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;
    const contractAddress = req.query.contractAddress as string | undefined;

    // Log request
    console.log("[getSupplied] → request", {
      pool,
      network,
      provider: provider ?? "(null)",
      providerKey: providerKey ? "***" : "(null)",
      contractAddress
    });

    // Validate
    if (!pool || !network || !contractAddress || !asset) {
      console.log("[getSupplied] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, asset, contractAddress",
      });
    }
    console.log("[getSupplied] … fetching pool data");
    const { suppliedAmount } = await getSupplied(pool, asset, network, provider, providerKey, contractAddress);

    console.log("[getSupplied] ✓ success", { ms: Date.now() - t0, data: suppliedAmount });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "getSupplied invoked succesfully.",
      data: suppliedAmount,
    });
  } catch (err: any) {
    console.log("[getSupplied] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({
      status: "fail",
      status_code: 400,
      message: err?.message || String(err),
    });
  }
});
lendingRouter.get("/getBorrowed", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    type RpcNetworkFromHelper = Parameters<typeof rpc>[0]; // same trick as your HF route
    const pool = req.query.pool as string | undefined;
    const network = req.query.network as RpcNetworkFromHelper | undefined;
    const asset = req.query.asset as string | undefined;
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;
    const contractAddress = req.query.contractAddress as string | undefined;

    console.log("[getBorrowed] → request", {
      pool,
      network,
      provider: provider ?? "(null)",
      providerKey: providerKey ? "***" : "(null)",
      contractAddress
    });

    if (!pool || !network || !contractAddress || !asset) {
      console.log("[getBorrowed] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, asset, contractAddress",
      });
    }
    console.log("[getBorrowed] … fetching pool data");
    const { borrowedAmount } = await getBorrowed(pool, asset, network, provider, providerKey, contractAddress);

    console.log("[getBorrowed] ✓ success", { ms: Date.now() - t0, data: borrowedAmount });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "getBorrowed invoked succesfully.",
      data: borrowedAmount,
    });
  } catch (err: any) {
    console.log("[getBorrowed] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({
      status: "fail",
      status_code: 400,
      message: err?.message || String(err),
    });
  }
});
// ─── AAVE v3 pool addresses per network ───────────────────────────────────────
const AAVE_V3_POOL: Partial<Record<string, string>> = {
  base: "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
  optimism: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  polygon: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  arbitrum: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  ethereum: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
};

// Fluid chain IDs
const FLUID_CHAIN_ID: Partial<Record<string, number>> = {
  base: 8453,
  ethereum: 1,
  arbitrum: 42161,
};

// FLUID fToken addresses for common underlying assets per network
// fToken address → can also be passed directly via query param
const FLUID_FTOKENS: Partial<Record<string, Partial<Record<string, string>>>> = {
  base: {
    "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913": "0xf42f5795d9ac7e9d757db633d693cd548cfd9169", // USDC → fUSDC
  }
};

// Compound V3 (Comet) market addresses per network — underlying → comet
const COMPOUND_V3_MARKETS: Partial<Record<string, Partial<Record<string, string>>>> = {
  base: {
    "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913": "0xb125E6687d4313864e53df431d5425969c15Eb2F", // USDC → cUSDCv3
    "0x4200000000000000000000000000000000000006": "0x46e6b214b524310239732D51387075E0e70970bf", // WETH → cWETHv3
  },
  ethereum: {
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "0xc3d688B66703497DAA19211EEdff47f25384cdc3", // USDC → cUSDCv3
    "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "0xA17581A9E3356d9A858b789D68B4d866e593aE94", // WETH → cWETHv3
  },
  optimism: {
    "0x0b2c639c533813f4aa9d7837caf62653d097ff85": "0x2e44e174f7D53F0212823acC11C01A11d58c5bCB", // USDC → cUSDCv3
  },
};

const ICometAbi = [
  "function getUtilization() view returns (uint256)",
  "function getSupplyRate(uint256 utilization) view returns (uint64)",
  "function getBorrowRate(uint256 utilization) view returns (uint64)",
];

const IPoolAprAbi = [
  "function getReserveData(address asset) view returns (uint256 configuration, uint128 liquidityIndex, uint128 currentLiquidityRate, uint128 variableBorrowIndex, uint128 currentVariableBorrowRate, uint128 currentStableBorrowRate, uint40 lastUpdateTimestamp, uint16 id, address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress, address interestRateStrategyAddress, uint128 accruedToTreasury, uint128 unbacked, uint128 isolationModeTotalDebt)"
];

// Convert ray (1e27) rate to APY: (1 + rate/1e27)^365 - 1
function rayToAPY(rayBN: BigNumber): number {
  const RAY = BigNumber.from("1000000000000000000000000000");
  // Use float arithmetic — precision is fine for display purposes
  const ratePerDay = Number(rayBN.mul(1e9).div(RAY)) / 1e9 / 365;
  return Math.pow(1 + ratePerDay, 365) - 1;
}

lendingRouter.get("/getSupplyAPY", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    const platform = ((req.query.platform as string) || "aave").toLowerCase();
    const network = (req.query.network as string | undefined)?.toLowerCase();
    const asset = req.query.asset as string | undefined;
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;

    console.log("[getSupplyAPY] →", { platform, network, asset });

    if (!network || !asset) {
      return res.status(400).json({ status: "fail", status_code: 400, message: "Missing required params: network, asset" });
    }

    let apy: number;

    if (platform === "aave") {
      const poolAddr = AAVE_V3_POOL[network];
      if (!poolAddr) return res.status(400).json({ status: "fail", status_code: 400, message: `No AAVE pool known for network: ${network}` });
      const ethersProvider = new ethers.providers.JsonRpcProvider(rpc(network as any, provider, providerKey));
      const pool = new ethers.Contract(poolAddr, IPoolAprAbi, ethersProvider);
      const data = await pool.callStatic.getReserveData(asset);
      apy = rayToAPY(data.currentLiquidityRate);

    } else if (platform === "fluid") {
      const chainId = FLUID_CHAIN_ID[network];
      if (!chainId) return res.status(400).json({ status: "fail", status_code: 400, message: `No Fluid chain ID for network: ${network}` });

      // Resolve fToken address
      let fToken = req.query.fToken as string | undefined;
      if (!fToken) fToken = FLUID_FTOKENS[network]?.[asset.toLowerCase()];
      if (!fToken) return res.status(400).json({ status: "fail", status_code: 400, message: `Unknown Fluid fToken for asset ${asset} on ${network}. Pass fToken param.` });

      const url = `https://api.fluid.instadapp.io/v2/lending/${chainId}/tokens/${fToken}`;
      console.log("[getSupplyAPY] Fluid API →", url);
      const resp = await fetch(url);
      if (!resp.ok) throw new Error(`Fluid API error: ${resp.status} ${resp.statusText}`);
      const json: any = await resp.json();
      // totalRate is 1e2 precision: 100 = 1%, 10000 = 100%
      const totalRate: number = json?.data?.totalRate ?? json?.totalRate;
      if (totalRate === undefined || totalRate === null) throw new Error("Fluid API did not return totalRate");
      apy = totalRate / 10000; // convert to decimal fraction

    } else if (platform === "compound") {
      const cometAddr = COMPOUND_V3_MARKETS[network]?.[asset.toLowerCase()];
      if (!cometAddr) return res.status(400).json({ status: "fail", status_code: 400, message: `No Compound V3 market for asset ${asset} on ${network}. Pass market= or check COMPOUND_V3_MARKETS.` });
      const ethersProvider = new ethers.providers.JsonRpcProvider(rpc(network as any, provider, providerKey));
      const comet = new ethers.Contract(cometAddr, ICometAbi, ethersProvider);
      const utilization = await comet.getUtilization();
      const ratePerSec: BigNumber = await comet.getSupplyRate(utilization);
      // rate is per second in 1e18 units
      const SECONDS_PER_YEAR = 365 * 24 * 3600;
      apy = Math.pow(1 + Number(ratePerSec) / 1e18, SECONDS_PER_YEAR) - 1;

    } else {
      return res.status(400).json({ status: "fail", status_code: 400, message: `Unknown platform: ${platform}. Use 'aave', 'fluid', or 'compound'.` });
    }

    console.log("[getSupplyAPY] ✓", { apy, ms: Date.now() - t0 });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "getSupplyAPY invoked successfully.",
      data: { apy, apy_percent: +(apy * 100).toFixed(4) },
    });
  } catch (err: any) {
    console.log("[getSupplyAPY] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({ status: "fail", status_code: 400, message: err?.message || String(err) });
  }
});

lendingRouter.get("/getBorrowAPY", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    const platform = ((req.query.platform as string) || "aave").toLowerCase();
    const network = (req.query.network as string | undefined)?.toLowerCase();
    const asset = req.query.asset as string | undefined;
    const provider = (req.query.provider as string | undefined) ?? null;
    const providerKey = (req.query.providerKey as string | undefined) ?? null;

    console.log("[getBorrowAPY] →", { platform, network, asset });

    if (!network || !asset) {
      return res.status(400).json({ status: "fail", status_code: 400, message: "Missing required params: network, asset" });
    }

    let apy: number;

    if (platform === "aave") {
      const poolAddr = AAVE_V3_POOL[network];
      if (!poolAddr) return res.status(400).json({ status: "fail", status_code: 400, message: `No AAVE pool known for network: ${network}` });
      const ethersProvider = new ethers.providers.JsonRpcProvider(rpc(network as any, provider, providerKey));
      const pool = new ethers.Contract(poolAddr, IPoolAprAbi, ethersProvider);
      const data = await pool.callStatic.getReserveData(asset);
      apy = rayToAPY(data.currentVariableBorrowRate);

    } else if (platform === "compound") {
      const cometAddr = COMPOUND_V3_MARKETS[network]?.[asset.toLowerCase()];
      if (!cometAddr) return res.status(400).json({ status: "fail", status_code: 400, message: `No Compound V3 market for asset ${asset} on ${network}.` });
      const ethersProvider = new ethers.providers.JsonRpcProvider(rpc(network as any, provider, providerKey));
      const comet = new ethers.Contract(cometAddr, ICometAbi, ethersProvider);
      const utilization = await comet.getUtilization();
      const ratePerSec: BigNumber = await comet.getBorrowRate(utilization);
      const SECONDS_PER_YEAR = 365 * 24 * 3600;
      apy = Math.pow(1 + Number(ratePerSec) / 1e18, SECONDS_PER_YEAR) - 1;

    } else {
      return res.status(400).json({ status: "fail", status_code: 400, message: `getBorrowAPY not supported for platform: ${platform}` });
    }

    console.log("[getBorrowAPY] ✓", { apy, ms: Date.now() - t0 });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "getBorrowAPY invoked successfully.",
      data: { apy, apy_percent: +(apy * 100).toFixed(4) },
    });
  } catch (err: any) {
    console.log("[getBorrowAPY] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({ status: "fail", status_code: 400, message: err?.message || String(err) });
  }
});

// ── GET /getTokenBalance ───────────────────────────────────────────────────────
// Returns the raw ERC-20 balance of `asset` held by `wallet` on `network`.
// Used by strategies to check vault token balances before repay/harvest.
lendingRouter.get("/getTokenBalance", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    // Address validation here; network validation is owned by the API gateway.
    const network = ((req.query.network as string | undefined) ?? "").toLowerCase();
    if (!network) return res.status(400).json({ status: "fail", status_code: 400, message: "network parameter missing" });
    const walletAddress = assertAddress(req.query.wallet as string | undefined, "wallet");
    const asset = assertAddress(req.query.asset as string | undefined, "asset");

    const ethersProvider = new ethers.providers.JsonRpcProvider(rpc(network as any));
    const tokenAbi = [
      "function balanceOf(address account) view returns (uint256)",
      "function decimals() view returns (uint8)"
    ];
    const token = new ethers.Contract(asset, tokenAbi, ethersProvider);
    const [balanceWei, decimals]: [BigNumber, number] = await Promise.all([
      token.balanceOf(walletAddress),
      token.decimals()
    ]);
    const balance = ethers.utils.formatUnits(balanceWei, decimals);

    console.log("[getTokenBalance] ✓", { network, wallet: walletAddress, asset, balance, ms: Date.now() - t0 });
    return res.status(200).json({
      status: "success",
      status_code: 200,
      message: "getTokenBalance invoked successfully.",
      data: { balance, balanceWei: balanceWei.toString(), decimals }
    });
  } catch (err: any) {
    console.log("[getTokenBalance] ! error", { message: err?.message || String(err), ms: Date.now() - t0 });
    return res.status(400).json({ status: "fail", status_code: 400, message: err?.message || String(err) });
  }
});

export default lendingRouter;
