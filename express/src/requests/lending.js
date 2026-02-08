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
var pool_1 = require("../utils/pool");
var txOptions_1 = require("../utils/txOptions");
var dhedge_1 = require("../dhedge");
var txFees_1 = require("../txFees");
var AAVE_1 = require("../utils/AAVE");
var ERC20_1 = require("../utils/ERC20");
function toBigAmount(amountDecStr, decimals) {
    var s = amountDecStr.trim();
    if (!/^\d+(\.\d+)?$/.test(s))
        throw new Error("amount must be a decimal string");
    return v2_sdk_1.ethers.utils.parseUnits(s, decimals);
}
// percent (0–100, up to 2 dp) to bps (0–10000)
function percentToBps(percentStr) {
    var n = Number(percentStr);
    if (!isFinite(n))
        throw new Error("share must be numeric");
    if (n <= 0 || n > 100)
        throw new Error("share must be in (0,100]");
    return Math.round(n * 100); // 12.34% -> 1234 bps
}
var lendingRouter = (0, express_1.Router)();
lendingRouter.post("/borrow", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, asset, manager, dHedge, poolAddress, pool, provider, key, apiKey, amount, string_amount, txOptions, tx, dApp, platform, estimatedGas, txOptions2, err_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 10, , 11]);
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw "Network parameter missing";
                asset = req.query.asset;
                manager = null;
                dHedge = void 0;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                poolAddress = req.query.pool;
                pool = void 0;
                provider = null;
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
                dHedge = _a.sent();
                return [4 /*yield*/, dHedge.loadPool(poolAddress)];
            case 2:
                pool = _a.sent();
                return [3 /*break*/, 5];
            case 3: return [4 /*yield*/, (0, dhedge_1.dhedge)(network, manager).loadPool(poolAddress)];
            case 4:
                pool = _a.sent();
                _a.label = 5;
            case 5:
                amount = void 0;
                //const composition = await pool.getComposition();
                //const balance = getBalanceFromComposition(asset,composition);
                //if (req.query.share) {
                //        const share = req.query.share as string;
                //        amount = balance.mul(share).div(100);
                //}
                if (req.query.amount) {
                    string_amount = req.query.amount;
                    amount = v2_sdk_1.ethers.BigNumber.from(string_amount);
                    //if (amount.gt(balance)) amount === balance;
                }
                else
                    throw "share or amount parameters missing";
                return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 6:
                txOptions = _a.sent();
                tx = void 0;
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "aave" || platform == "aavev3")
                        dApp = v2_sdk_1.Dapp.AAVEV3;
                    else
                        throw "Unsupported lending/borrowing protocol";
                }
                else
                    throw "platform parameter missing";
                estimatedGas = null;
                return [4 /*yield*/, pool.borrow(dApp, asset, amount, 0, txOptions, true)];
            case 7:
                estimatedGas = _a.sent();
                console.log("estimated gas for repay tx");
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 8:
                txOptions2 = _a.sent();
                return [4 /*yield*/, pool.borrow(dApp, asset, amount, 0, txOptions2, false)];
            case 9:
                tx = _a.sent();
                console.log("repay transaction:");
                console.log(tx);
                if (apiKey) {
                    console.log("Sending API payment");
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 11];
            case 10:
                err_1 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_1 });
                return [3 /*break*/, 11];
            case 11: return [2 /*return*/];
        }
    });
}); });
lendingRouter.post("/repay", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, asset, manager, dHedge, poolAddress, pool, provider, key, apiKey, amount, composition, balance, share, string_amount, txOptions, tx, dApp, platform, estimatedGas, txOptions2, err_2;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 11, , 12]);
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw "Network parameter missing";
                asset = req.query.asset;
                manager = null;
                dHedge = void 0;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                poolAddress = req.query.pool;
                pool = void 0;
                provider = null;
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
                dHedge = _a.sent();
                return [4 /*yield*/, dHedge.loadPool(poolAddress)];
            case 2:
                pool = _a.sent();
                return [3 /*break*/, 5];
            case 3: return [4 /*yield*/, (0, dhedge_1.dhedge)(network, manager).loadPool(poolAddress)];
            case 4:
                pool = _a.sent();
                _a.label = 5;
            case 5:
                amount = void 0;
                return [4 /*yield*/, pool.getComposition()];
            case 6:
                composition = _a.sent();
                balance = (0, pool_1.getBalanceFromComposition)(asset, composition);
                if (req.query.share) {
                    share = req.query.share;
                    amount = balance.mul(share).div(100);
                }
                else if (req.query.amount) {
                    string_amount = req.query.amount;
                    amount = v2_sdk_1.ethers.BigNumber.from(string_amount);
                    if (amount.gt(balance))
                        amount = balance;
                }
                else
                    throw "share or amount parameters missing";
                return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 7:
                txOptions = _a.sent();
                tx = void 0;
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "aave" || platform == "aavev3")
                        dApp = v2_sdk_1.Dapp.AAVEV3;
                    else if (platform == "compound")
                        dApp = "compoundv3";
                    else
                        throw "Unsupported lending/borrowing protocol";
                }
                else
                    throw "platform parameter missing";
                estimatedGas = null;
                return [4 /*yield*/, pool.repay(dApp, asset, amount, txOptions, true)];
            case 8:
                estimatedGas = _a.sent();
                console.log("estimated gas for repay tx");
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 9:
                txOptions2 = _a.sent();
                return [4 /*yield*/, pool.repay(dApp, asset, amount, txOptions2, false)];
            case 10:
                tx = _a.sent();
                console.log("repay transaction:");
                console.log(tx);
                if (apiKey) {
                    console.log("Sending API payment");
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 12];
            case 11:
                err_2 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_2 });
                return [3 /*break*/, 12];
            case 12: return [2 /*return*/];
        }
    });
}); });
lendingRouter.post("/lend", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, dApp, platform, asset, manager, dHedge, poolAddress, pool, provider, key, apiKey, share, lendAmount, amount, composition, balance, decimals, shareStr, shareNum, decStr, txOptions, estimatedGas, txOptions2, tx, err_3;
    var _a, _b, _c, _d;
    return __generator(this, function (_e) {
        switch (_e.label) {
            case 0:
                _e.trys.push([0, 12, , 13]);
                console.log("/lend: endpoint invoked");
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw new Error("/lend: Network parameter missing");
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "aave" || platform == "aavev3")
                        dApp = v2_sdk_1.Dapp.AAVEV3;
                    else
                        throw new Error("/lend: Unsupported platform");
                }
                else
                    throw new Error("/lend: platform parameter missing");
                asset = req.query.asset;
                manager = null;
                dHedge = void 0;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                poolAddress = req.query.pool;
                pool = void 0;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                apiKey = null;
                share = null;
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
                lendAmount = void 0;
                amount = void 0;
                console.log("/lend: fetching pool composition");
                return [4 /*yield*/, pool.getComposition()];
            case 6:
                composition = _e.sent();
                balance = (0, pool_1.getBalanceFromComposition)(asset, composition);
                console.log("/lend: [rpc] network/provider/key", { network: network, provider: provider, key: key });
                return [4 /*yield*/, (0, ERC20_1.getTokenDecimals)(asset, network, provider, key)];
            case 7:
                decimals = _e.sent();
                if (req.query.share != null) {
                    shareStr = String(req.query.share);
                    shareNum = Number.parseFloat(shareStr);
                    if (!Number.isFinite(shareNum)) {
                        throw new Error("/lend: invalid share");
                    }
                    lendAmount = balance.mul(Math.floor(shareNum)).div(100);
                    decStr = String(req.query.amount);
                    amount = toBigAmount(decStr, decimals);
                    lendAmount = amount;
                }
                else {
                    throw new Error("/lend: share or amount parameters missing");
                }
                return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 8:
                txOptions = _e.sent();
                console.log("/lend: tx Options to use:");
                console.log(txOptions);
                // estimate gas
                console.log("/lend: estimated gas for the tx");
                return [4 /*yield*/, pool.lend(dApp, asset, lendAmount, 0, txOptions, true)];
            case 9:
                estimatedGas = _e.sent();
                console.log((_b = (_a = estimatedGas === null || estimatedGas === void 0 ? void 0 : estimatedGas.toString) === null || _a === void 0 ? void 0 : _a.call(estimatedGas)) !== null && _b !== void 0 ? _b : estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, (_d = (_c = estimatedGas === null || estimatedGas === void 0 ? void 0 : estimatedGas.toString) === null || _c === void 0 ? void 0 : _c.call(estimatedGas)) !== null && _d !== void 0 ? _d : null)];
            case 10:
                txOptions2 = _e.sent();
                // send tx
                console.log("/lend: transaction");
                return [4 /*yield*/, pool.lend(dApp, asset, lendAmount, 0, txOptions2, false)];
            case 11:
                tx = _e.sent();
                console.log(tx);
                if (apiKey) {
                    console.log("/lend: Sending API payment");
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 13];
            case 12:
                err_3 = _e.sent();
                res.status(400).send({ status: "fail", msg: err_3 instanceof Error ? err_3.message : String(err_3) });
                return [3 /*break*/, 13];
            case 13: return [2 /*return*/];
        }
    });
}); });
lendingRouter.post("/unlend", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, dApp, platform, asset, manager, dHedge, poolAddress, pool, provider, key, apiKey, share, unlendAmount, amount, decimals, decStr, txOptions, estimatedGas, txOptions2, tx, err_4;
    var _a, _b, _c, _d;
    return __generator(this, function (_e) {
        switch (_e.label) {
            case 0:
                _e.trys.push([0, 11, , 12]);
                console.log("/unlend: endpoint invoked");
                network = void 0;
                if (req.query.network)
                    network = req.query.network;
                else
                    throw new Error("/unlend: Network parameter missing");
                dApp = void 0;
                if (req.query.platform) {
                    platform = req.query.platform.toLowerCase();
                    if (platform == "aave" || platform == "aavev3")
                        dApp = v2_sdk_1.Dapp.AAVEV3;
                    else
                        throw new Error("/unlend: Unsupported platform");
                }
                else
                    throw new Error("/unlend: platform parameter missing");
                asset = req.query.asset;
                manager = null;
                dHedge = void 0;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                poolAddress = req.query.pool;
                pool = void 0;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                apiKey = null;
                share = null;
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
                unlendAmount = void 0;
                amount = void 0;
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
                console.log("/unlend: [rpc] network/provider/key", { network: network, provider: provider, key: key });
                return [4 /*yield*/, (0, ERC20_1.getTokenDecimals)(asset, network, provider, key)];
            case 6:
                decimals = _e.sent();
                if (req.query.share != null) {
                    share = req.query.share;
                    throw new Error("/unlend: share parameter not implemented yet");
                    //console.log("unlendAmount using share")
                    //unlendAmount = balance.mul(share).div(100);
                    //console.log(unlendAmount)
                }
                else if (req.query.amount != null) {
                    console.log("amount decimal in string");
                    decStr = String(req.query.amount);
                    console.log(decStr);
                    console.log("amount in big number");
                    amount = toBigAmount(decStr, decimals); // convert decimal -> BigNumber
                    console.log(amount);
                }
                else {
                    throw new Error("/unlend: share or amount parameters missing");
                }
                return [4 /*yield*/, (0, txOptions_1.getTxOptions)(pool.network, provider, key)];
            case 7:
                txOptions = _e.sent();
                console.log("/unlend: default tx Options to use:");
                console.log(txOptions);
                // estimate gas
                console.log("/unlend: estimated gas for the tx");
                return [4 /*yield*/, pool.withdrawDeposit(dApp, asset, amount, txOptions, true)];
            case 8:
                estimatedGas = _e.sent();
                console.log((_b = (_a = estimatedGas === null || estimatedGas === void 0 ? void 0 : estimatedGas.toString) === null || _a === void 0 ? void 0 : _a.call(estimatedGas)) !== null && _b !== void 0 ? _b : estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, (_d = (_c = estimatedGas === null || estimatedGas === void 0 ? void 0 : estimatedGas.toString) === null || _c === void 0 ? void 0 : _c.call(estimatedGas)) !== null && _d !== void 0 ? _d : null)];
            case 9:
                txOptions2 = _e.sent();
                // send tx
                console.log("/unlend: executing withdrawDeposit tx");
                return [4 /*yield*/, pool.withdrawDeposit(dApp, asset, amount, txOptions2, false)];
            case 10:
                tx = _e.sent();
                console.log(tx);
                if (apiKey) {
                    console.log("/unlend: Sending API payment");
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 12];
            case 11:
                err_4 = _e.sent();
                res.status(400).send({ status: "fail", msg: err_4 instanceof Error ? err_4.message : String(err_4) });
                return [3 /*break*/, 12];
            case 12: return [2 /*return*/];
        }
    });
}); });
lendingRouter.get("/getHealthFactor", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var t0, pool, network, platform, provider, providerKey, contractAddress, result, healthFactor, err_5;
    var _a, _b, _c;
    return __generator(this, function (_d) {
        switch (_d.label) {
            case 0:
                t0 = Date.now();
                _d.label = 1;
            case 1:
                _d.trys.push([1, 3, , 4]);
                pool = req.query.pool;
                network = req.query.network;
                platform = (_a = req.query.platform) === null || _a === void 0 ? void 0 : _a.toLowerCase();
                provider = (_b = req.query.provider) !== null && _b !== void 0 ? _b : null;
                providerKey = (_c = req.query.providerKey) !== null && _c !== void 0 ? _c : null;
                contractAddress = req.query.contractAddress;
                // Log request
                console.log("[HF] → request", {
                    pool: pool,
                    network: network,
                    platform: platform,
                    provider: provider !== null && provider !== void 0 ? provider : "(null)",
                    providerKey: providerKey ? "***" : "(null)",
                    contractAddress: contractAddress
                });
                // Validate
                if (!pool || !network || !platform || !contractAddress) {
                    console.log("[HF] ✖ missing params");
                    return [2 /*return*/, res.status(400).json({
                            status: "fail",
                            status_code: 400,
                            message: "Missing required params: pool, network, platform, contractAddress",
                        })];
                }
                if (platform !== "aave" && platform !== "aavev3") {
                    console.log("[HF] ✖ unsupported platform:", platform);
                    return [2 /*return*/, res.status(400).json({
                            status: "fail",
                            status_code: 400,
                            message: "Unsupported platform",
                        })];
                }
                console.log("[HF] … computing health factor");
                return [4 /*yield*/, (0, AAVE_1.getAaveV3HealthFactor)(pool, network, provider, providerKey, contractAddress)];
            case 2:
                result = _d.sent();
                healthFactor = typeof result === "number" ? result : result.healthFactor;
                console.log("[HF] ✓ success", { healthFactor: healthFactor, ms: Date.now() - t0 });
                return [2 /*return*/, res.status(200).json({
                        status: "success",
                        status_code: 200,
                        data: { healthFactor: healthFactor },
                    })];
            case 3:
                err_5 = _d.sent();
                console.log("[HF] ! error", { message: (err_5 === null || err_5 === void 0 ? void 0 : err_5.message) || String(err_5), ms: Date.now() - t0 });
                return [2 /*return*/, res.status(400).json({
                        status: "fail",
                        status_code: 400,
                        message: (err_5 === null || err_5 === void 0 ? void 0 : err_5.message) || String(err_5),
                    })];
            case 4: return [2 /*return*/];
        }
    });
}); });
lendingRouter.get("/getPoolAaveData", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var t0, pool, network, provider, providerKey, contractAddress, formatted, err_6;
    var _a, _b;
    return __generator(this, function (_c) {
        switch (_c.label) {
            case 0:
                t0 = Date.now();
                _c.label = 1;
            case 1:
                _c.trys.push([1, 3, , 4]);
                pool = req.query.pool;
                network = req.query.network;
                provider = (_a = req.query.provider) !== null && _a !== void 0 ? _a : null;
                providerKey = (_b = req.query.providerKey) !== null && _b !== void 0 ? _b : null;
                contractAddress = req.query.contractAddress;
                // Log request
                console.log("[/getPoolAaveData] → request", {
                    pool: pool,
                    network: network,
                    provider: provider !== null && provider !== void 0 ? provider : "(null)",
                    providerKey: providerKey ? "***" : "(null)",
                    contractAddress: contractAddress
                });
                // Validate
                if (!pool || !network || !contractAddress) {
                    console.log("[/getPoolAaveData] ✖ missing params");
                    return [2 /*return*/, res.status(400).json({
                            status: "fail",
                            status_code: 400,
                            message: "Missing required params: pool, network, platform, contractAddress",
                        })];
                }
                console.log("[/getPoolAaveData] … fetching pool data");
                return [4 /*yield*/, (0, AAVE_1.getPoolAaveData)(pool, network, provider, providerKey, contractAddress)];
            case 2:
                formatted = (_c.sent()).formatted;
                console.log("[/getPoolAaveData] ✓ success", { ms: Date.now() - t0, data: formatted });
                return [2 /*return*/, res.status(200).json({
                        status: "success",
                        status_code: 200,
                        message: "/getPoolAaveData invoked succesfully",
                        data: formatted,
                    })];
            case 3:
                err_6 = _c.sent();
                console.log("[/getPoolAaveData] ! error", { message: (err_6 === null || err_6 === void 0 ? void 0 : err_6.message) || String(err_6), ms: Date.now() - t0 });
                return [2 /*return*/, res.status(400).json({
                        status: "fail",
                        status_code: 400,
                        message: (err_6 === null || err_6 === void 0 ? void 0 : err_6.message) || String(err_6),
                    })];
            case 4: return [2 /*return*/];
        }
    });
}); });
lendingRouter.get("/getSupplied", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var t0, pool, network, asset, provider, providerKey, contractAddress, suppliedAmount, err_7;
    var _a, _b;
    return __generator(this, function (_c) {
        switch (_c.label) {
            case 0:
                t0 = Date.now();
                _c.label = 1;
            case 1:
                _c.trys.push([1, 3, , 4]);
                pool = req.query.pool;
                network = req.query.network;
                asset = req.query.asset;
                provider = (_a = req.query.provider) !== null && _a !== void 0 ? _a : null;
                providerKey = (_b = req.query.providerKey) !== null && _b !== void 0 ? _b : null;
                contractAddress = req.query.contractAddress;
                // Log request
                console.log("[getSupplied] → request", {
                    pool: pool,
                    network: network,
                    provider: provider !== null && provider !== void 0 ? provider : "(null)",
                    providerKey: providerKey ? "***" : "(null)",
                    contractAddress: contractAddress
                });
                // Validate
                if (!pool || !network || !contractAddress || !asset) {
                    console.log("[getSupplied] ✖ missing params");
                    return [2 /*return*/, res.status(400).json({
                            status: "fail",
                            status_code: 400,
                            message: "Missing required params: pool, network, asset, contractAddress",
                        })];
                }
                console.log("[getSupplied] … fetching pool data");
                return [4 /*yield*/, (0, AAVE_1.getSupplied)(pool, asset, network, provider, providerKey, contractAddress)];
            case 2:
                suppliedAmount = (_c.sent()).suppliedAmount;
                console.log("[getSupplied] ✓ success", { ms: Date.now() - t0, data: suppliedAmount });
                return [2 /*return*/, res.status(200).json({
                        status: "success",
                        status_code: 200,
                        message: "getSupplied invoked succesfully.",
                        data: suppliedAmount,
                    })];
            case 3:
                err_7 = _c.sent();
                console.log("[getSupplied] ! error", { message: (err_7 === null || err_7 === void 0 ? void 0 : err_7.message) || String(err_7), ms: Date.now() - t0 });
                return [2 /*return*/, res.status(400).json({
                        status: "fail",
                        status_code: 400,
                        message: (err_7 === null || err_7 === void 0 ? void 0 : err_7.message) || String(err_7),
                    })];
            case 4: return [2 /*return*/];
        }
    });
}); });
lendingRouter.get("/getBorrowed", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var t0, pool, network, asset, provider, providerKey, contractAddress, borrowedAmount, err_8;
    var _a, _b;
    return __generator(this, function (_c) {
        switch (_c.label) {
            case 0:
                t0 = Date.now();
                _c.label = 1;
            case 1:
                _c.trys.push([1, 3, , 4]);
                pool = req.query.pool;
                network = req.query.network;
                asset = req.query.asset;
                provider = (_a = req.query.provider) !== null && _a !== void 0 ? _a : null;
                providerKey = (_b = req.query.providerKey) !== null && _b !== void 0 ? _b : null;
                contractAddress = req.query.contractAddress;
                console.log("[getBorrowed] → request", {
                    pool: pool,
                    network: network,
                    provider: provider !== null && provider !== void 0 ? provider : "(null)",
                    providerKey: providerKey ? "***" : "(null)",
                    contractAddress: contractAddress
                });
                if (!pool || !network || !contractAddress || !asset) {
                    console.log("[getBorrowed] ✖ missing params");
                    return [2 /*return*/, res.status(400).json({
                            status: "fail",
                            status_code: 400,
                            message: "Missing required params: pool, network, asset, contractAddress",
                        })];
                }
                console.log("[getBorrowed] … fetching pool data");
                return [4 /*yield*/, (0, AAVE_1.getBorrowed)(pool, asset, network, provider, providerKey, contractAddress)];
            case 2:
                borrowedAmount = (_c.sent()).borrowedAmount;
                console.log("[getBorrowed] ✓ success", { ms: Date.now() - t0, data: borrowedAmount });
                return [2 /*return*/, res.status(200).json({
                        status: "success",
                        status_code: 200,
                        message: "getBorrowed invoked succesfully.",
                        data: borrowedAmount,
                    })];
            case 3:
                err_8 = _c.sent();
                console.log("[getBorrowed] ! error", { message: (err_8 === null || err_8 === void 0 ? void 0 : err_8.message) || String(err_8), ms: Date.now() - t0 });
                return [2 /*return*/, res.status(400).json({
                        status: "fail",
                        status_code: 400,
                        message: (err_8 === null || err_8 === void 0 ? void 0 : err_8.message) || String(err_8),
                    })];
            case 4: return [2 /*return*/];
        }
    });
}); });
exports.default = lendingRouter;
