import { Dapp, ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { BigNumber } from "ethers"
const tradeRouter = Router();
import { Request, Response } from "express";
import { getBalanceFromComposition } from "../utils/pool";
import { getTxOptions } from "../utils/txOptions";
import { dhedge,dhedgev2 } from "../dhedge";
import { wallet } from "../wallet";
import { walletv2 } from "../walletv2";
import { apiPayment, feeData, txFees } from "../txFees";
import { rpc } from "../rpc";



// helper: wait with a timeout + status check
async function waitForSuccess(tx: ethers.providers.TransactionResponse, timeoutMs = 30_000, confirmations = 1) {
  const timer = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("Transaction receipt timeout")), timeoutMs)
  );
  const receipt = await Promise.race([
    tx.wait(confirmations),
    timer,
  ]);
  if (!receipt || receipt.status !== 1) {
    throw new Error(`Transaction failed or reverted (hash: ${tx.hash})`);
  }
  return receipt;
}

const erc20ABI = JSON.stringify([
    // Minimal ERC20 ABI for allowance and approve
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)"
]);

const MAX_ALLOWANCE = ethers.constants.MaxUint256
async function checkAllowance(network: Network, assetAddress: string, contractAddress: string, poolAddress: string,provider: string | null,key: string | null) {
  try {
    const url = rpc(network,provider,key)
    const rpc_provider = new ethers.providers.JsonRpcProvider(url);
    const tokenContract = new ethers.Contract(assetAddress, erc20ABI, rpc_provider);
    const allowed = await tokenContract.allowance(poolAddress, contractAddress);
    return allowed.eq(MAX_ALLOWANCE)
   }
   catch(error) { throw error }
}

tradeRouter.get("/checkAllowance", async (req: Request, res: Response) => {
  try {
    let network: Network = Network.POLYGON; 
    if (req.query.network) network = req.query.network as Network;
    const assetAddress = req.query.asset as string;
    const contractAddress = req.query.contract as string;
    const poolAddress = req.query.pool as string;
    let manager = null; let apiKey = null; let provider = null; let key = null;
    if (req.query.provider) provider = req.query.provider as string; 
    if (req.query.key) key = req.query.key as string; 
    else manager = "infinitetrading" 
    if (req.query.manager) manager = req.query.manager as string;
    if (!ethers.utils.isAddress(assetAddress)) throw new Error(`Invalid asset address: ${assetAddress}`);
    if (!ethers.utils.isAddress(contractAddress)) throw new Error(`Invalid contract address: ${contractAddress}`);
    if (!ethers.utils.isAddress(poolAddress)) throw new Error(`Invalid pool address: ${poolAddress}`);
    const isAllowed = await checkAllowance(network,assetAddress,contractAddress,poolAddress,provider,key);
    res.status(200).send({ status: "success", msg: isAllowed });
  } catch (error) { res.status(400).send({ status: "fail", msg: error }); }
});

tradeRouter.post("/approve", async (req: Request, res: Response) => {
  try {
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    const poolAddress = req.query.pool as string;
    let manager = null; let provider = 'alchemy'; let key = null; 
    if (req.query.provider) provider = req.query.provider as string;
    if (req.query.key) key = req.query.key as string;
    let apiKey; let pool;
    if (req.query.manager) manager = req.query.manager as string;
    if (req.query.apiKey) {
            apiKey = req.query.apiKey as string;
            let dHedge = await dhedgev2(network,apiKey,provider,key)
            pool = await dHedge.loadPool(poolAddress);
    }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    const txOptions = await getTxOptions(pool.network,provider,key);
    let dApp;
    if (req.query.platform) {
        const platform = (req.query.platform as string).toLowerCase();
        if (platform == "uniswapv3") dApp = "uniswapV3" as Dapp
        else if (platform == "oneinch") dApp = Dapp.ONEINCH;
        else if (platform == "1inch") dApp = Dapp.ONEINCH;
        else if (platform == "aave" || platform == "aavev3") dApp = Dapp.AAVEV3;
        else dApp = req.query.platform as Dapp;
    }
    else throw "platform parameter missing"
    const estimatedGas = await pool.approve(dApp,req.body.asset,ethers.constants.MaxUint256,txOptions,{ estimateGas: true });
    console.log("estimated gas for approve:");
    console.log(estimatedGas);
    const txOptions2 = await txFees(network,provider,key,estimatedGas);
    const tx = await pool.approve(dApp,req.body.asset,MAX_ALLOWANCE,txOptions2);
    console.log(tx);
    const receipt = await tx.wait();
    console.log('Transaction mined:', receipt);
    if (req.query.apiKey) {
        console.log("Sending API payment");
        apiKey = req.query.apiKey as string;
        apiPayment(network,apiKey,tx,provider,key,null);
    }
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) { res.status(400).send({ status: "fail", msg: err }); }
});

tradeRouter.get("/trade", async (req: Request, res: Response) => {
  try {
    console.log("trade endpoint invoked")
    let network: Network;
    if (req.query.network) network = req.query.network as Network;
    else throw "Network parameter missing"
    let withdrawal = false;
    if (req.query.withdrawal !== undefined) {
        withdrawal = req.query.withdrawal === "true" || req.query.withdrawal === "1";
    }
    const assetA = req.query.from as string;
    const assetB = req.query.to as string;
    let manager = null; let dHedge;
    if (req.query.manager) { manager = req.query.manager as string; }
    const slippage = req.query.slippage as string;
    const poolAddress = req.query.pool as string;
    let feeAmount = 500;
    if (req.query.feeAmount) { feeAmount = req.query.feeAmount as unknown as number; }
    let pool; let provider = 'infura'; let key = null;
    if (req.query.provider) { provider = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }
    let apiKey = null;
    if (req.query.apiKey) { apiKey = req.query.apiKey as string; }
    if (apiKey) { dHedge =  await dhedgev2(network,apiKey,provider,key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network,manager).loadPool(poolAddress);
    let tradeAmount: ethers.BigNumber;
    const composition = await pool.getComposition();
    const balance = getBalanceFromComposition(assetA,composition);
    if (req.query.share) {
            const share = req.query.share as string;
            tradeAmount = balance.mul(share).div(100);
    }
    else if (req.query.amount) {
        const amount = req.query.amount as string;
        tradeAmount = ethers.BigNumber.from(amount);
        if (tradeAmount.gt(balance)) tradeAmount = balance;
    }
    else throw "share or amount parameters missing";

    const txOptions = await getTxOptions(pool.network,provider,key);
    let tx; let dApp: Dapp;
    if (req.query.platform) {
            const platform = (req.query.platform as string).toLowerCase();
            if (platform == "uniswapv3") dApp = "uniswapV3" as Dapp;
            else if (platform == "oneinch") dApp = Dapp.ONEINCH;
            else if (platform == "1inch") dApp = Dapp.ONEINCH;
            else dApp = platform as Dapp;
    }
    else throw "platform parameter missing"
    let txHashes = [];
    let paymentTx = null;
    if (dApp == Dapp.UNISWAPV3) {
            let estimatedGas;
            estimatedGas = await pool.tradeUniswapV3(assetA,assetB,tradeAmount,feeAmount,+slippage,txOptions,{ estimateGas: true });
            console.log("estimating gas for uniswapV3")
            console.log(estimatedGas)
            const txOptions2 = await txFees(network,provider,key,estimatedGas);
            tx = await pool.tradeUniswapV3(assetA,assetB,tradeAmount,feeAmount,+slippage,txOptions2);
            console.log("trade transaction for uniswapV3")
            console.log(tx)
            txHashes.push(tx.hash);
            paymentTx = tx;
    }
    else {
        let estimatedGas = null
        if (dApp === Dapp.TOROS) {
                // --- First transaction ---
                const estGas1 = await pool.trade(Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions, { estimateGas: true });
                console.log("Estimated gas for Toros trade:", estGas1);

                const txOptions1 = await txFees(network, provider, key, estGas1?.toString?.() ?? null);
                const tx1 = await pool.trade(Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions1);
                console.log("Toros trade tx:", tx1);

                txHashes.push(tx1.hash);
                paymentTx = tx1;
                const r1 = await waitForSuccess(tx1, 45_000, 1);
                console.log("Toros trade mined. gasUsed:", r1.gasUsed.toString());

                // --- Conditional second transaction ---
                if (withdrawal) {
                        const estGas2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions, { estimateGas: true });
                        console.log("Estimated gas for Toros Withdrawal:", estGas2);
                        const txOptions2 = await txFees(network, provider, key, estGas2?.toString?.() ?? null);
                        const tx2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions2);

                        console.log("Toros withdrawal tx:", tx2);
                        txHashes.push(tx2.hash);
                        tx = tx2;
                } else { tx = tx1; }    
        }
            else {
                if (req.query.platform != "toros" && req.query.platform != "oneinch" && req.query.platform != "1inch") estimatedGas = await pool.trade(dApp,assetA,assetB,tradeAmount,+slippage,txOptions,{ estimateGas: true });
                console.log("estimated gas for odos trade")
                console.log(estimatedGas)
                const txOptions2 = await txFees(network,provider,key,estimatedGas);
                tx = await pool.trade(dApp,assetA,assetB,tradeAmount,+slippage,txOptions2);
                console.log("odos trade transaction:")
                console.log(tx)
                txHashes.push(tx.hash);
                paymentTx = tx;
            }
    }

    if (apiKey && paymentTx) {
        console.log("Sending API payment");
        await apiPayment(network, apiKey, paymentTx, provider, key, null);
    }

    res.status(200).send({ status: "success", msg: txHashes });
  }
  catch (err) {
    console.error("Trade error:", err);
    const message = (err instanceof Error) ? err.message : JSON.stringify(err);
    res.status(400).send({ status: "fail", msg: message });
  }
});

export default tradeRouter;
