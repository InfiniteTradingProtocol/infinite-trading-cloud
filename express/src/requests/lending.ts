import { Dapp, ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { BigNumber } from "ethers"
import { Request, Response } from "express";
import { getBalanceFromComposition } from "../utils/pool";
import { getTxOptions } from "../utils/txOptions";
import { dhedge,dhedgev2 } from "../dhedge";
import { wallet } from "../wallet";
import { walletv2 } from "../walletv2";
import { apiPayment, feeData, txFees } from "../txFees";
import { rpc } from "../rpc";
import { getPoolAaveData, getAaveV3HealthFactor,getSupplied,getBorrowed } from "../utils/AAVE";
import { getTokenDecimals } from "../utils/ERC20";

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
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
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

    const txOptions = await getTxOptions(pool.network,provider,key);
    let tx; let dApp: Dapp;

    if (req.query.platform) {
            const platform = (req.query.platform as string).toLowerCase();
            if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
            else throw "Unsupported lending/borrowing protocol";
    }

    else throw "platform parameter missing"

    let estimatedGas = null
    estimatedGas = await pool.borrow(dApp,asset,amount,0,txOptions,true);
    console.log("estimated gas for repay tx")
    console.log(estimatedGas)
    const txOptions2 = await txFees(network,provider,key,estimatedGas);
    tx = await pool.borrow(dApp,asset,amount,0,txOptions2,false);
    console.log("repay transaction:")
    console.log(tx)
    if (apiKey) { console.log("Sending API payment"); apiPayment(network,apiKey,tx,provider,key,null) }

    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
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
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    let amount: ethers.BigNumber;
    const composition = await pool.getComposition();
    const balance = getBalanceFromComposition(asset,composition);
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

    const txOptions = await getTxOptions(pool.network,provider,key);
    let tx; let dApp: Dapp;
    
    if (req.query.platform) {
            const platform = (req.query.platform as string).toLowerCase();
            if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
            else if (platform == "compound") dApp = "compoundv3" as Dapp;
            else throw "Unsupported lending/borrowing protocol";
    }
    else throw "platform parameter missing"
    
    let estimatedGas = null
    estimatedGas = await pool.repay(dApp,asset,amount,txOptions,true);
    console.log("estimated gas for repay tx")
    console.log(estimatedGas)
    const txOptions2 = await txFees(network,provider,key,estimatedGas);
    tx = await pool.repay(dApp,asset,amount,txOptions2,false);
    console.log("repay transaction:")
    console.log(tx)
    if (apiKey) { console.log("Sending API payment"); apiPayment(network,apiKey,tx,provider,key,null) }

    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
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
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    let lendAmount: ethers.BigNumber; let amount: ethers.BigNumber;
    console.log("/lend: fetching pool composition")
    const composition = await pool.getComposition();
    //console.log("one composition entry:", composition[0]);
    const balance = getBalanceFromComposition(asset,composition);
    console.log("/lend: [rpc] network/provider/key", { network, provider, key });
    const decimals = await getTokenDecimals(asset,network,provider,key);
    if (req.query.share != null) {
    const shareStr = String(req.query.share);
    const shareNum = Number.parseFloat(shareStr);
    if (!Number.isFinite(shareNum)) { throw new Error("/lend: invalid share"); }
  	lendAmount = balance.mul(Math.floor(shareNum)).div(100);
  	const decStr = String(req.query.amount);
  	amount = toBigAmount(decStr, decimals);
  	lendAmount = amount;
   } else {
  	throw new Error("/lend: share or amount parameters missing");
    }
    const txOptions = await getTxOptions(pool.network,provider,key);
    console.log("/lend: tx Options to use:");
    console.log(txOptions);

    // estimate gas
    console.log("/lend: estimated gas for the tx");
    const estimatedGas = await pool.lend(dApp, asset, lendAmount, 0, txOptions, true);
    console.log(estimatedGas?.toString?.() ?? estimatedGas);

    // produce final overrides
    const txOptions2 = await txFees(network, provider, key, estimatedGas?.toString?.() ?? null);

   // send tx
   console.log("/lend: transaction");
   const tx = await pool.lend(dApp, asset, lendAmount, 0, txOptions2, false);
   console.log(tx);
   if (apiKey) { console.log("/lend: Sending API payment"); apiPayment(network,apiKey,tx,provider,key,null) }
    res.status(200).send({ status: "success", msg: tx.hash });
    } catch (err) {
  	res.status(400).send({ status: "fail", msg: err instanceof Error ? err.message : String(err) });
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
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    let unlendAmount: ethers.BigNumber; let amount: ethers.BigNumber;
    
    // *************************
    //
    // I NEED TO REPLACE THIS
    //
    // TO FETCH THE BALANCE DIRECTLY FROM THE AAVE POSITIONS OF THIS VAULT
    //
    // ************************
    //
    //console.log("/lend: fetching pool composition")
    
    //const composition = await pool.getComposition();
    
    //console.log("one composition entry:", composition[0]);
    //const balance = getBalanceFromComposition(asset,composition);
    
    console.log("/unlend: [rpc] network/provider/key", { network, provider, key });
    const decimals = await getTokenDecimals(asset,network,provider,key);
    if (req.query.share != null) {
        share = req.query.share
        throw new Error("/unlend: share parameter not implemented yet")
	//console.log("unlendAmount using share")
        //unlendAmount = balance.mul(share).div(100);
        //console.log(unlendAmount)
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

    const txOptions = await getTxOptions(pool.network,provider,key);
    console.log("/unlend: default tx Options to use:");
    console.log(txOptions);

    // estimate gas
    console.log("/unlend: estimated gas for the tx");
    const estimatedGas = await pool.withdrawDeposit(dApp, asset, amount, txOptions, true);
    console.log(estimatedGas?.toString?.() ?? estimatedGas);

    // produce final overrides
    const txOptions2 = await txFees(network, provider, key, estimatedGas?.toString?.() ?? null);

   // send tx
   console.log("/unlend: executing withdrawDeposit tx");
   const tx = await pool.withdrawDeposit(dApp, asset, amount, txOptions2, false);
   console.log(tx);
   if (apiKey) { console.log("/unlend: Sending API payment"); apiPayment(network,apiKey,tx,provider,key,null) }
    res.status(200).send({ status: "success", msg: tx.hash });
    } catch (err) {
        res.status(400).send({ status: "fail", msg: err instanceof Error ? err.message : String(err) });
   }
});

lendingRouter.get("/getHealthFactor", async (req: Request, res: Response) => {
  const t0 = Date.now();
  try {
    // Parse
    type RpcNetwork = Parameters<typeof rpc>[0];
    const pool            = req.query.pool as string | undefined;
    const network         = req.query.network as RpcNetwork | undefined;
    const platform        = (req.query.platform as string | undefined)?.toLowerCase();
    const provider        = (req.query.provider as string | undefined) ?? null;
    const providerKey     = (req.query.providerKey as string | undefined) ?? null;
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
    const pool            = req.query.pool as string | undefined;
    const network         = req.query.network as RpcNetworkFromHelper | undefined;
    const provider        = (req.query.provider as string | undefined) ?? null;
    const providerKey     = (req.query.providerKey as string | undefined) ?? null;
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
    const { formatted }= await getPoolAaveData(
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
    const pool            = req.query.pool as string | undefined;
    const network         = req.query.network as RpcNetworkFromHelper | undefined;
    const asset		  = req.query.asset as string | undefined;
    const provider        = (req.query.provider as string | undefined) ?? null;
    const providerKey     = (req.query.providerKey as string | undefined) ?? null;
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
    if (!pool || !network || !contractAddress || !asset ) {
      console.log("[getSupplied] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, asset, contractAddress",
      });
    }
    console.log("[getSupplied] … fetching pool data");
    const { suppliedAmount }= await getSupplied(pool, asset, network, provider, providerKey, contractAddress);

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
    const pool            = req.query.pool as string | undefined;
    const network         = req.query.network as RpcNetworkFromHelper | undefined;
    const asset           = req.query.asset as string | undefined;
    const provider        = (req.query.provider as string | undefined) ?? null;
    const providerKey     = (req.query.providerKey as string | undefined) ?? null;
    const contractAddress = req.query.contractAddress as string | undefined;

    console.log("[getBorrowed] → request", {
      pool,
      network,
      provider: provider ?? "(null)",
      providerKey: providerKey ? "***" : "(null)",
      contractAddress
    });

    if (!pool || !network || !contractAddress || !asset ) {
      console.log("[getBorrowed] ✖ missing params");
      return res.status(400).json({
        status: "fail",
        status_code: 400,
        message: "Missing required params: pool, network, asset, contractAddress",
      });
    }
    console.log("[getBorrowed] … fetching pool data");
    const { borrowedAmount }= await getBorrowed(pool, asset, network, provider, providerKey, contractAddress);

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
export default lendingRouter;
