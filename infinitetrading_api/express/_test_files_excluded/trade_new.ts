import { Dapp, ethers, Network } from "@dhedge/v2-sdk";
import { Router } from "express";
import { BigNumber } from "ethers"
const tradeRouter = Router();
import { Request, Response } from "express";
import { getBalanceFromComposition } from "../utils/pool";
import { getTxOptions } from "../utils/txOptions";
import { dhedge, dhedgev2 } from "../dhedge";
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

//jest.setTimeout(100000);

//(async () => {
//    const assetAddress = '0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6';
//    const contractAddress = '0xb48a390270d41a1663a68708210b7ef4d89ba9f6';
//    const amount = ethers.utils.parseEther("100");
//    console.log(amount)
//    // The network variable was removed since it's not used in this scope.
//    const erc20ABI = '[{"constant":true,"inputs":[{"name":"owner","type":"address"},{"name":"spender","type":"address"}],"name":"allowance","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}]'; // Simplified ABI for demonstration
//    const manager = 'infinitetrading'; // Ensure you have this function correctly defined to return a signer
//    let network = Network.POLYGON;
//    const signer = wallet(network,manager); // Assuming wallet returns a correctly initialized ethers.Signer
//    await checkallowance(assetAddress, contractAddress, amount, erc20ABI, signer);
//    estimateGasForMethod();
//})();

const erc20ABI = JSON.stringify([
  // Minimal ERC20 ABI for allowance and approve
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)"
]);

const MAX_ALLOWANCE = ethers.constants.MaxUint256
async function checkAllowance(network: Network, assetAddress: string, contractAddress: string, poolAddress: string, provider: string | null, key: string | null) {
  try {
    const url = rpc(network, provider, key)
    const rpc_provider = new ethers.providers.JsonRpcProvider(url);
    const tokenContract = new ethers.Contract(assetAddress, erc20ABI, rpc_provider);
    const allowed = await tokenContract.allowance(poolAddress, contractAddress);
    return allowed.eq(MAX_ALLOWANCE)
  }
  catch (error) { throw error }
}

tradeRouter.get("/checkAllowance", async (req: Request, res: Response) => {
  try {
    let network: Network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const assetAddress = req.body.asset;
    const contractAddress = req.body.contract;
    const poolAddress = req.body.pool;
    let manager = null; let apiKey = null; let provider = null; let key = null;
    if (req.query.provider) provider = req.query.provider as string;
    if (req.query.key) key = req.query.key as string;
    else manager = "infinitetrading"
    if (req.query.manager) manager = req.query.manager as string;
    if (!ethers.utils.isAddress(assetAddress)) throw new Error(`Invalid asset address: ${assetAddress}`);
    if (!ethers.utils.isAddress(contractAddress)) throw new Error(`Invalid contract address: ${contractAddress}`);
    if (!ethers.utils.isAddress(poolAddress)) throw new Error(`Invalid pool address: ${poolAddress}`);
    const isAllowed = await checkAllowance(network, assetAddress, contractAddress, poolAddress, provider, key);
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
      let dHedge = await dhedgev2(network, apiKey, provider, key)
      //console.log(dHedge)
      pool = await dHedge.loadPool(poolAddress);
    }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    const txOptions = await getTxOptions(pool.network, provider, key);
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
    const estimatedGas = await pool.approve(dApp, req.body.asset, ethers.constants.MaxUint256, txOptions, { estimateGas: true });
    console.log("estimated gas for approve:");
    console.log(estimatedGas);
    const txOptions2 = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.approve(dApp, req.body.asset, MAX_ALLOWANCE, txOptions2);
    console.log(tx);
    const receipt = await tx.wait();
    console.log('Transaction mined:', receipt);
    if (req.query.apiKey) {
      console.log("Sending API payment");
      apiKey = req.query.apiKey as string;
      apiPayment(network, apiKey, tx, provider, key, null);
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
    if (apiKey) { dHedge = await dhedgev2(network, apiKey, provider, key); pool = await dHedge.loadPool(poolAddress); }
    else pool = await dhedge(network, manager).loadPool(poolAddress);
    let tradeAmount: ethers.BigNumber;
    const composition = await pool.getComposition();
    const balance = getBalanceFromComposition(assetA, composition);
    if (req.query.share) {
      const share = req.query.share as string;
      tradeAmount = balance.mul(share).div(100);
    }
    else if (req.query.amount) {
      const amount = req.query.amount as string;
      tradeAmount = ethers.BigNumber.from(amount);
      //tradeAmount = ethers.utils.parseEther(amount);
      if (tradeAmount.gt(balance)) tradeAmount = balance;
    }
    else throw "share or amount parameters missing";

    const txOptions = await getTxOptions(pool.network, provider, key);
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
      estimatedGas = await pool.tradeUniswapV3(assetA, assetB, tradeAmount, feeAmount, +slippage, txOptions, { estimateGas: true });
      console.log("estimating gas for uniswapV3")
      console.log(estimatedGas)
      const txOptions2 = await txFees(network, provider, key, estimatedGas);
      tx = await pool.tradeUniswapV3(assetA, assetB, tradeAmount, feeAmount, +slippage, txOptions2);
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
        paymentTx = tx1; // ✅ only tx1 is used for API payment
        const r1 = await waitForSuccess(tx1, 45_000, 1);
        console.log("Toros trade mined. gasUsed:", r1.gasUsed.toString());

        // --- Conditional second transaction ---
        if (withdrawal) {
          const estGas2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions, { estimateGas: true });
          console.log("Estimated gas for Toros Withdrawal:", estGas2);
          const txOptions2 = await txFees(network, provider, key, estGas2?.toString?.() ?? null);
          const tx2 = await pool.completeTorosWithdrawal(assetB, +slippage, txOptions2, false);

          console.log("Toros withdrawal tx:", tx2);
          txHashes.push(tx2.hash);
          tx = tx2; // If withdrawal happens, tx2 is the final transaction
        } else { tx = tx1; }
      }
      else {
        if (req.query.platform != "toros" && req.query.platform != "oneinch" && req.query.platform != "1inch") estimatedGas = await pool.trade(dApp, assetA, assetB, tradeAmount, +slippage, txOptions, { estimateGas: true });
        console.log("estimated gas for fallback swap")
        console.log(estimatedGas)
        const txOptions2 = await txFees(network, provider, key, estimatedGas);
        tx = await pool.trade(dApp, assetA, assetB, tradeAmount, +slippage, txOptions2);
        console.log("fallback swap transaction:")
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

//export const allowanceDelta = async (
//  owner: string,
//  asset: string,
//  spender: string,
//  signer: Wallet
//): Promise<BigNumber> => {
//  const block = await signer.provider.getBlockNumber();
//  const iERC20 = new Contract(asset, IERC20.abi, signer);
//  const [allowanceBefore, allowanceAfter] = await Promise.all(
//    [block - 1, block].map(e =>
//      iERC20.allowance(owner, spender, { blockTag: e })
//    )
//  );
//  return allowanceAfter.sub(allowanceBefore);
//};

//
//implement this endpoints
//  async claimFees(
//    dapp: Dapp,
//    tokenId: string,
//    options: any = null,
//    estimateGas = false
//  ):
//async addLiquidityV2(
//    dapp: Dapp.VELODROMEV2 | Dapp.RAMSES | Dapp.AERODROME,
//    assetA: string,
//    assetB: string,
//    amountA: BigNumber | string,
//    amountB: BigNumber | string,
//    isStable: boolean,
//    options: any = null,
//    estimateGas = false
//):
//
//removeLiquidityV2(
//    dapp: Dapp.VELODROMEV2 | Dapp.RAMSES | Dapp.AERODROME,
//    assetA: string,
//    assetB: string,
//    amount: BigNumber | string,
//    isStable: boolean,
//    options: any = null,
//    estimateGas = false
//  ):

// Connect to an Ethereum provider (you can use Infura, Alchemy, or any other provider)
//const provider = new ethers.providers.InfuraProvider("mainnet", "YOUR_INFURA_PROJECT_ID");
// or for Alchemy
// const provider = new ethers.providers.AlchemyProvider("mainnet", "YOUR_ALCHEMY_API_KEY");
//traderRouter.post("/getGasPrice", async (req: Request, res: Response) => {
//  try {
// Get the current gas price
//    const gasPrice = await provider.getGasPrice();
// Convert the gas price from wei to gwei for better readability
//   const gasPriceInGwei = ethers.utils.formatUnits(gasPrice, "gwei");
//    console.log(`Current gas price: ${gasPriceInGwei} Gwei`);
// } catch (error) {
//    console.error("Error fetching gas price:", error);
// }
//}

//tradeRouter.post("/newapprove", async (req, res) => {
//    try {
//        // Set default network to Polygon, but allow override from request
//        let network = Network.POLYGON;
//        if (req.query.network) network = req.query.network;

//        const poolAddress = req.query.pool;

// Manager can be null, in which case the default private key is used
//        let manager = null;
//        if (req.query.manager) manager = req.query.manager;

// Create a wallet instance for signing
//      const signer = wallet(network, manager);

// Check the current allowance
//    const allowance = await token.allowance(await signer.getAddress(), poolAddress);

//  if (allowance.lt(ethers.constants.MaxUint256)) {
// If allowance is insufficient, proceed with the approval
// Assuming pool.approve is a correct method call in your context, you might need to adjust this
// Perhaps directly use the `token` contract to call approve if needed
//    const tx = await token.approve(poolAddress, ethers.constants.MaxUint256);

// Wait for the transaction to be mined
//  await tx.wait();

//res.status(200).send({ status: "success", message: tx.hash });
// } else {
// If the current allowance is already sufficient
//   res.status(200).send({ status: "success", message: "Approval is not required. Allowance is sufficient." });
//}
//} catch (err) {
//    res.status(400).send({ status: "failure", message: err.message });
//}
//});


export default tradeRouter;
