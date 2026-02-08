"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var v2_sdk_1 = require("@dhedge/v2-sdk");
var express_1 = require("express");
var tradeRouter = (0, express_1.Router)();
var pool_1 = require("../utils/pool");
var txOptions_1 = require("../utils/txOptions");
var dhedge_1 = require("../dhedge");
var txFees_1 = require("../txFees");
var rpc_1 = require("../rpc");
// helper: wait with a timeout + status check
function waitForSuccess(tx_1) {
    return __awaiter(this, arguments, void 0, function (tx, timeoutMs, confirmations) {
        var timer, receipt;
        if (timeoutMs === void 0) { timeoutMs = 30000; }
        if (confirmations === void 0) { confirmations = 1; }
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    timer = new Promise(function (_, reject) {
                        return setTimeout(function () { return reject(new Error("Transaction receipt timeout")); }, timeoutMs);
                    });
                    return [4 /*yield*/, Promise.race([
                            tx.wait(confirmations),
                            timer,
                        ])];
                case 1:
                    receipt = _a.sent();
                    if (!receipt || receipt.status !== 1) {
                        throw new Error("Transaction failed or reverted (hash: ".concat(tx.hash, ")"));
                    }
                    return [2 /*return*/, receipt];
            }
        });
    });
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
var erc20ABI = JSON.stringify([
    // Minimal ERC20 ABI for allowance and approve
    "function allowance(address owner, address spender) external view returns (uint256)",
    "function approve(address spender, uint256 amount) external returns (bool)"
]);
var MAX_ALLOWANCE = v2_sdk_1.ethers.constants.MaxUint256;
function checkAllowance(network, assetAddress, contractAddress, poolAddress, provider, key) {
    return __awaiter(this, void 0, void 0, function () {
        var url, rpc_provider, tokenContract, allowed, error_1;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 2, , 3]);
                    url = (0, rpc_1.rpc)(network, provider, key);
                    rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider(url);
                    tokenContract = new v2_sdk_1.ethers.Contract(assetAddress, erc20ABI, rpc_provider);
                    return [4 /*yield*/, tokenContract.allowance(poolAddress, contractAddress)];
                case 1:
                    allowed = _a.sent();
                    return [2 /*return*/, allowed.eq(MAX_ALLOWANCE)];
                case 2:
                    error_1 = _a.sent();
                    throw error_1;
                case 3: return [2 /*return*/];
            }
        });
    });
}
tradeRouter.get("/checkAllowance", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, assetAddress, contractAddress, poolAddress, manager, apiKey, provider, key, isAllowed, error_2;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 2, , 3]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                assetAddress = req.body.asset;
                contractAddress = req.body.contract;
                poolAddress = req.body.pool;
                manager = null;
                apiKey = null;
                provider = null;
                key = null;
                if (req.query.provider)
                    provider = req.query.provider;
                if (req.query.key)
                    key = req.query.key;
                else
                    manager = "infinitetrading";
                if (req.query.manager)
                    manager = req.query.manager;
                if (!v2_sdk_1.ethers.utils.isAddress(assetAddress))
                    throw new Error("Invalid asset address: ".concat(assetAddress));
                if (!v2_sdk_1.ethers.utils.isAddress(contractAddress))
                    throw new Error("Invalid contract address: ".concat(contractAddress));
                if (!v2_sdk_1.ethers.utils.isAddress(poolAddress))
                    throw new Error("Invalid pool address: ".concat(poolAddress));
                return [4 /*yield*/, checkAllowance(network, assetAddress, contractAddress, poolAddress, provider, key)];
            case 1:
                isAllowed = _a.sent();
                res.status(200).send({ status: "success", msg: isAllowed });
                return [3 /*break*/, 3];
            case 2:
                error_2 = _a.sent();
                res.status(400).send({ status: "fail", msg: error_2 });
                return [3 /*break*/, 3];
            case 3: return [2 /*return*/];
        }
    });
}); });
tradeRouter.post("/approve", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, manager, provider, key, apiKey, pool, dHedge, txOptions, dApp, platform, estimatedGas, txOptions2, tx, receipt, err_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 11, , 12]);
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw "Network parameter missing";
                poolAddress = req.query.pool;
                manager = null;
                provider = 'alchemy';
                key = null;
                if (req.query.provider)
                    provider = req.query.provider;
                if (req.query.key)
                    key = req.query.key;
                apiKey = void 0;
                pool = void 0;
                if (req.query.manager)
                    manager = req.query.manager;
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                return [4 /*yield*/, (0, dhedge_1.dhedgev2)(network, apiKey, provider, key)
                    //console.log(dHedge)
                ];
            case 1:
                dHedge = _a.sent();
                return [4 /*yield*/, dHedge.loadPool(poolAddress)];
            case 2:
                //console.log(dHedge)
                pool = _a.sent();
                return [3 /*break*/, 5];
            case 3: return [4 /*yield*/, (0, dhedge_1.dhedge)(network, manager).loadPool(poolAddress)];
            case 4:
                pool = _a.sent();
                _a.label = 5;
            case 5: return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 6:
                txOptions = _a.sent();
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "uniswapv3")
                        dApp = "uniswapV3";
                    else if (platform == "oneinch")
                        dApp = v2_sdk_1.Dapp.ONEINCH;
                    else if (platform == "1inch")
                        dApp = v2_sdk_1.Dapp.ONEINCH;
                    else if (platform == "aave" || platform == "aavev3")
                        dApp = v2_sdk_1.Dapp.AAVEV3;
                    else
                        dApp = req.query.platform;
                }
                else
                    throw "platform parameter missing";
                return [4 /*yield*/, pool.approve(dApp, req.body.asset, v2_sdk_1.ethers.constants.MaxUint256, txOptions, true)];
            case 7:
                estimatedGas = _a.sent();
                console.log("estimated gas for approve:");
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 8:
                txOptions2 = _a.sent();
                return [4 /*yield*/, pool.approve(dApp, req.body.asset, MAX_ALLOWANCE, txOptions2)];
            case 9:
                tx = _a.sent();
                console.log(tx);
                return [4 /*yield*/, tx.wait()];
            case 10:
                receipt = _a.sent();
                console.log('Transaction mined:', receipt);
                if (req.query.apiKey) {
                    console.log("Sending API payment");
                    apiKey = req.query.apiKey;
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 12];
            case 11:
                err_1 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_1 });
                return [3 /*break*/, 12];
            case 12: return [2 /*return*/];
        }
    });
}); });
tradeRouter.get("/trade", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, withdrawal, assetA, assetB, manager, dHedge, slippage, poolAddress, feeAmount, pool, provider, key, apiKey, tradeAmount, composition, balance, share, amount, txOptions, tx, dApp, platform, txHashes, paymentTx, estimatedGas, txOptions2, estimatedGas, estGas1, txOptions1, tx1, r1, estGas2, txOptions2, tx2, txOptions2, err_2, message;
    var _a, _b, _c, _d;
    return __generator(this, function (_e) {
        switch (_e.label) {
            case 0:
                _e.trys.push([0, 29, , 30]);
                console.log("trade endpoint invoked");
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw "Network parameter missing";
                withdrawal = false;
                if (req.query.withdrawal !== undefined) {
                    withdrawal = req.query.withdrawal === "true" || req.query.withdrawal === "1";
                }
                assetA = req.query.from;
                assetB = req.query.to;
                manager = null;
                dHedge = void 0;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                slippage = req.query.slippage;
                poolAddress = req.query.pool;
                feeAmount = 500;
                if (req.query.feeAmount) {
                    feeAmount = req.query.feeAmount;
                }
                pool = void 0;
                provider = 'infura';
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                apiKey = null;
                if (req.query.apiKey) {
                    apiKey = req.query.apiKey;
                }
                if (!apiKey) return [3 /*break*/, 3];
                return [4 /*yield*/, (0, dhedge_1.dhedgev2)(network, apiKey, provider, key)];
            case 1:
                dHedge = _e.sent();
                return [4 /*yield*/, dHedge.loadPool(poolAddress)];
            case 2:
                pool = _e.sent();
                return [3 /*break*/, 5];
            case 3: return [4 /*yield*/, (0, dhedge_1.dhedge)(network, manager).loadPool(poolAddress)];
            case 4:
                pool = _e.sent();
                _e.label = 5;
            case 5:
                tradeAmount = void 0;
                return [4 /*yield*/, pool.getComposition()];
            case 6:
                composition = _e.sent();
                balance = (0, pool_1.getBalanceFromComposition)(assetA, composition);
                if (req.query.share) {
                    share = req.query.share;
                    tradeAmount = balance.mul(share).div(100);
                }
                else if (req.query.amount) {
                    amount = req.query.amount;
                    tradeAmount = v2_sdk_1.ethers.BigNumber.from(amount);
                    //tradeAmount = ethers.utils.parseEther(amount);
                    if (tradeAmount.gt(balance))
                        tradeAmount = balance;
                }
                else
                    throw "share or amount parameters missing";
                return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 7:
                txOptions = _e.sent();
                tx = void 0;
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "uniswapv3")
                        dApp = "uniswapV3";
                    else if (platform == "oneinch")
                        dApp = v2_sdk_1.Dapp.ONEINCH;
                    else if (platform == "1inch")
                        dApp = v2_sdk_1.Dapp.ONEINCH;
                    else
                        dApp = platform;
                }
                else
                    throw "platform parameter missing";
                txHashes = [];
                paymentTx = null;
                if (!(dApp == v2_sdk_1.Dapp.UNISWAPV3)) return [3 /*break*/, 11];
                estimatedGas = void 0;
                return [4 /*yield*/, pool.tradeUniswapV3(assetA, assetB, tradeAmount, feeAmount, +slippage, txOptions, true)];
            case 8:
                estimatedGas = _e.sent();
                console.log("estimating gas for uniswapV3");
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 9:
                txOptions2 = _e.sent();
                return [4 /*yield*/, pool.tradeUniswapV3(assetA, assetB, tradeAmount, feeAmount, +slippage, txOptions2)];
            case 10:
                tx = _e.sent();
                console.log("trade transaction for uniswapV3");
                console.log(tx);
                txHashes.push(tx.hash);
                paymentTx = tx;
                return [3 /*break*/, 26];
            case 11:
                estimatedGas = null;
                if (!(dApp === v2_sdk_1.Dapp.TOROS)) return [3 /*break*/, 21];
                return [4 /*yield*/, pool.trade(v2_sdk_1.Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions, true)];
            case 12:
                estGas1 = _e.sent();
                console.log("Estimated gas for Toros trade:", estGas1);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, (_b = (_a = estGas1 === null || estGas1 === void 0 ? void 0 : estGas1.toString) === null || _a === void 0 ? void 0 : _a.call(estGas1)) !== null && _b !== void 0 ? _b : null)];
            case 13:
                txOptions1 = _e.sent();
                return [4 /*yield*/, pool.trade(v2_sdk_1.Dapp.TOROS, assetA, assetB, tradeAmount, +slippage, txOptions1)];
            case 14:
                tx1 = _e.sent();
                console.log("Toros trade tx:", tx1);
                txHashes.push(tx1.hash);
                paymentTx = tx1; // ✅ only tx1 is used for API payment
                return [4 /*yield*/, waitForSuccess(tx1, 45000, 1)];
            case 15:
                r1 = _e.sent();
                console.log("Toros trade mined. gasUsed:", r1.gasUsed.toString());
                if (!withdrawal) return [3 /*break*/, 19];
                return [4 /*yield*/, pool.completeTorosWithdrawal(assetB, +slippage, txOptions, true)];
            case 16:
                estGas2 = _e.sent();
                console.log("Estimated gas for Toros Withdrawal:", estGas2);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, (_d = (_c = estGas2 === null || estGas2 === void 0 ? void 0 : estGas2.toString) === null || _c === void 0 ? void 0 : _c.call(estGas2)) !== null && _d !== void 0 ? _d : null)];
            case 17:
                txOptions2 = _e.sent();
                return [4 /*yield*/, pool.completeTorosWithdrawal(assetB, +slippage, txOptions2, false)];
            case 18:
                tx2 = _e.sent();
                console.log("Toros withdrawal tx:", tx2);
                txHashes.push(tx2.hash);
                tx = tx2; // If withdrawal happens, tx2 is the final transaction
                return [3 /*break*/, 20];
            case 19:
                tx = tx1;
                _e.label = 20;
            case 20: return [3 /*break*/, 26];
            case 21:
                if (!(req.query.platform != "toros" && req.query.platform != "oneinch" && req.query.platform != "1inch")) return [3 /*break*/, 23];
                return [4 /*yield*/, pool.trade(dApp, assetA, assetB, tradeAmount, +slippage, txOptions, true)];
            case 22:
                estimatedGas = _e.sent();
                _e.label = 23;
            case 23:
                console.log("estimated gas for odos trade");
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 24:
                txOptions2 = _e.sent();
                return [4 /*yield*/, pool.trade(dApp, assetA, assetB, tradeAmount, +slippage, txOptions2)];
            case 25:
                tx = _e.sent();
                console.log("odos trade transaction:");
                console.log(tx);
                txHashes.push(tx.hash);
                paymentTx = tx;
                _e.label = 26;
            case 26:
                if (!(apiKey && paymentTx)) return [3 /*break*/, 28];
                console.log("Sending API payment");
                return [4 /*yield*/, (0, txFees_1.apiPayment)(network, apiKey, paymentTx, provider, key, null)];
            case 27:
                _e.sent();
                _e.label = 28;
            case 28:
                res.status(200).send({ status: "success", msg: txHashes });
                return [3 /*break*/, 30];
            case 29:
                err_2 = _e.sent();
                console.error("Trade error:", err_2);
                message = (err_2 instanceof Error) ? err_2.message : JSON.stringify(err_2);
                res.status(400).send({ status: "fail", msg: message });
                return [3 /*break*/, 30];
            case 30: return [2 /*return*/];
        }
    });
}); });
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
exports.default = tradeRouter;
