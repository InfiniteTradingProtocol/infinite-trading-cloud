import { Network, SupportedAsset } from "@dhedge/v2-sdk";
import { Router } from "express";
import { ethers } from "ethers";

const adminRouter = Router();
import { Request, Response } from "express";
import { dhedge,dhedgev2 } from "../dhedge";
import { walletv2 } from "../walletv2";
import { apiPayment, feeData, txFees } from "../txFees";
import { rpc } from "../rpc";

//import { Mutex } from "async-mutex";

//const walletLocks = new Map<string, Mutex>();

//function getLockForKey(apiKey: string) {
//  if (!walletLocks.has(apiKey)) walletLocks.set(apiKey, new Mutex());
//  return walletLocks.get(apiKey)!;
//}

require("dotenv").config({ path: '../../.env' });
const ALCHEMY_BALANCES_KEY = process.env.ALCHEMY_BALANCES_KEY as string;

adminRouter.post("/createWallet", async (req: Request, res: Response) => {
try {
    const wallet = await ethers.Wallet.createRandom();
    res.status(200).send({status: "success",address: wallet.address,privateKey: wallet.privateKey});
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.post("/verifySignature", async (req: Request, res: Response) => {
  const { message, signature, expectedAddress } = req.body;

  if (!message || !signature || !expectedAddress) {
    return res.status(400).send({
      status: "fail",
      msg: "Missing message, signature, or expectedAddress",
    });
  }

  try {
    const recoveredAddress = ethers.utils.verifyMessage(message, signature);
    const isValid =
      recoveredAddress.toLowerCase() === expectedAddress.toLowerCase();

    return res.status(200).send({
      status: "success",
      isValid,
      recoveredAddress,
    });
  } catch (err) {
    return res.status(400).send({
      status: "fail",
      msg: "Invalid signature or verification error",
      error: err instanceof Error ? err.message : err,
    });
  }
});

adminRouter.post("/createPool", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key);
	pool = await dHedge.createPool(req.body.managerName,req.body.poolName,req.body.symbol,req.body.supportedAssets as unknown as SupportedAsset[],Number(req.body.fee));
    }
    else { pool = await dhedge(network,manager).createPool(req.body.managerName,req.body.poolName,req.body.symbol,req.body.supportedAssets as unknown as SupportedAsset[],Number(req.body.fee)); }
    res.status(200).send({
      status: "success",
      msg: pool.address,
    });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/getPool", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
	dHedge = await dhedgev2(network,apiKey,provider,key)
        pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    res.status(200).send({ status: "success", msg: pool });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/getSummary", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
	pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    res.status(200).send({ status: "success", msg: pool });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/getWallet", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    let wallet;
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null; 
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        wallet = await walletv2(network,apiKey,provider,key)
    }
    res.status(200).send({ status: "success", msg: wallet?.address ?? "N/A" });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/poolComposition", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge; let apiKey = 'none'; let provider = 'alchemy'; let key = ALCHEMY_BALANCES_KEY;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
    	const apiKey = req.query.apiKey as string;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
	pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    console.log(`📌 /poolComposition | 🌐 ${network} | 📌 ${poolAddress} | 🌐 ${provider} | 🗝️ ${key ?? "N/A"}`);
    const composition = await pool.getComposition();
    res.status(200).send({ status: "success", msg: composition });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/getManagerFee", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = 'infura'; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
        pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    const fees = await pool.getAvailableManagerFee();
    res.status(200).send({ status: "success", msg: fees });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.get("/mintManagerFee", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null; let provider = 'infura'; let key = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
        pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    let estimatedGas;
    estimatedGas = await pool.mintManagerFee(null,true);
    console.log(estimatedGas)
    const txOptions = await txFees(network,provider,key,estimatedGas);
    const tx = await pool.mintManagerFee(txOptions,false);
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        console.log("Sending API payment");
        apiPayment(network,apiKey,tx,provider,key,null)
    }
    res.status(200).send({ status: "success", msg: tx });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});
adminRouter.post("/changeAssets", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; } 
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
	pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress); }
    const tx = await pool.changeAssets(req.body.assets);
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    res.status(400).send({ status: "fail", msg: err });
  }
});

adminRouter.post("/setTrader", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
        const apiKey = req.query.apiKey as string;
        let provider = null; let key = null;
        if (req.query.provider) { provider = req.query.provider as string; }
        if (req.query.providerKey) { key = req.query.providerKey as string; }
        dHedge = await dhedgev2(network,apiKey,provider,key)
	pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network,manager).loadPool(poolAddress) }
    const tx = await pool.setTrader(req.body.traderAccount);
    res.status(200).send({ status: "success", status_code: 200, msg: tx.hash });
  } catch (err) {
    res.status(400).send({ status: "fail", status_code: 400, msg: err });
  }
});

export default adminRouter;
