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
var ethers_1 = require("ethers");
var adminRouter = (0, express_1.Router)();
var dhedge_1 = require("../dhedge");
var walletv2_1 = require("../walletv2");
var txFees_1 = require("../txFees");
//import { Mutex } from "async-mutex";
//const walletLocks = new Map<string, Mutex>();
//function getLockForKey(apiKey: string) {
//  if (!walletLocks.has(apiKey)) walletLocks.set(apiKey, new Mutex());
//  return walletLocks.get(apiKey)!;
//}
require("dotenv").config({ path: '../../.env' });
var ALCHEMY_BALANCES_KEY = process.env.ALCHEMY_BALANCES_KEY;
adminRouter.post("/createWallet", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var wallet, err_1;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 2, , 3]);
                return [4 /*yield*/, ethers_1.ethers.Wallet.createRandom()];
            case 1:
                wallet = _a.sent();
                res.status(200).send({ status: "success", address: wallet.address, privateKey: wallet.privateKey });
                return [3 /*break*/, 3];
            case 2:
                err_1 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_1 });
                return [3 /*break*/, 3];
            case 3: return [2 /*return*/];
        }
    });
}); });
adminRouter.post("/verifySignature", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var _a, message, signature, expectedAddress, recoveredAddress, isValid;
    return __generator(this, function (_b) {
        _a = req.body, message = _a.message, signature = _a.signature, expectedAddress = _a.expectedAddress;
        if (!message || !signature || !expectedAddress) {
            return [2 /*return*/, res.status(400).send({
                    status: "fail",
                    msg: "Missing message, signature, or expectedAddress",
                })];
        }
        try {
            recoveredAddress = ethers_1.ethers.utils.verifyMessage(message, signature);
            isValid = recoveredAddress.toLowerCase() === expectedAddress.toLowerCase();
            return [2 /*return*/, res.status(200).send({
                    status: "success",
                    isValid: isValid,
                    recoveredAddress: recoveredAddress,
                })];
        }
        catch (err) {
            return [2 /*return*/, res.status(400).send({
                    status: "fail",
                    msg: "Invalid signature or verification error",
                    error: err instanceof Error ? err.message : err,
                })];
        }
        return [2 /*return*/];
    });
}); });
adminRouter.post("/createPool", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, pool, dHedge, manager, apiKey, provider, key, err_2;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 6, , 7]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                return [4 /*yield*/, (0, dhedge_1.dhedgev2)(network, apiKey, provider, key)];
            case 1:
                dHedge = _a.sent();
                return [4 /*yield*/, dHedge.createPool(req.body.managerName, req.body.poolName, req.body.symbol, req.body.supportedAssets, Number(req.body.fee))];
            case 2:
                pool = _a.sent();
                return [3 /*break*/, 5];
            case 3: return [4 /*yield*/, (0, dhedge_1.dhedge)(network, manager).createPool(req.body.managerName, req.body.poolName, req.body.symbol, req.body.supportedAssets, Number(req.body.fee))];
            case 4:
                pool = _a.sent();
                _a.label = 5;
            case 5:
                res.status(200).send({
                    status: "success",
                    msg: pool.address,
                });
                return [3 /*break*/, 7];
            case 6:
                err_2 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_2 });
                return [3 /*break*/, 7];
            case 7: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/getPool", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, apiKey, provider, key, err_3;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 6, , 7]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
                res.status(200).send({ status: "success", msg: pool });
                return [3 /*break*/, 7];
            case 6:
                err_3 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_3 });
                return [3 /*break*/, 7];
            case 7: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/getSummary", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, apiKey, provider, key, err_4;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 6, , 7]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
                res.status(200).send({ status: "success", msg: pool });
                return [3 /*break*/, 7];
            case 6:
                err_4 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_4 });
                return [3 /*break*/, 7];
            case 7: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/getWallet", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, wallet, apiKey, provider, key, err_5;
    var _a;
    return __generator(this, function (_b) {
        switch (_b.label) {
            case 0:
                _b.trys.push([0, 3, , 4]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                wallet = void 0;
                if (!req.query.apiKey) return [3 /*break*/, 2];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                return [4 /*yield*/, (0, walletv2_1.walletv2)(network, apiKey, provider, key)];
            case 1:
                wallet = _b.sent();
                _b.label = 2;
            case 2:
                res.status(200).send({ status: "success", msg: (_a = wallet === null || wallet === void 0 ? void 0 : wallet.address) !== null && _a !== void 0 ? _a : "N/A" });
                return [3 /*break*/, 4];
            case 3:
                err_5 = _b.sent();
                res.status(400).send({ status: "fail", msg: err_5 });
                return [3 /*break*/, 4];
            case 4: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/poolComposition", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, apiKey, provider, key, manager, apiKey_1, composition, err_6;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 7, , 8]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                apiKey = 'none';
                provider = 'alchemy';
                key = ALCHEMY_BALANCES_KEY;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey_1 = req.query.apiKey;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
                return [4 /*yield*/, (0, dhedge_1.dhedgev2)(network, apiKey_1, provider, key)];
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
                console.log("\uD83D\uDCCC Endpoint: /poolComposition\n      \uD83C\uDF10 Network: ".concat(network, "\n      \uD83D\uDCCC Pool Address: ").concat(poolAddress, "\n      \uD83C\uDF10 Provider: ").concat(provider, "\n      \uD83D\uDDDD\uFE0F Provider Key: ").concat(key !== null && key !== void 0 ? key : "N/A", "\n    \t\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"));
                return [4 /*yield*/, pool.getComposition()];
            case 6:
                composition = _a.sent();
                res.status(200).send({ status: "success", msg: composition });
                return [3 /*break*/, 8];
            case 7:
                err_6 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_6 });
                return [3 /*break*/, 8];
            case 8: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/getManagerFee", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, apiKey, provider, key, fees, err_7;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 7, , 8]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = 'infura';
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
            case 5: return [4 /*yield*/, pool.getAvailableManagerFee()];
            case 6:
                fees = _a.sent();
                res.status(200).send({ status: "success", msg: fees });
                return [3 /*break*/, 8];
            case 7:
                err_7 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_7 });
                return [3 /*break*/, 8];
            case 8: return [2 /*return*/];
        }
    });
}); });
adminRouter.get("/mintManagerFee", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, provider, key, apiKey, estimatedGas, txOptions, tx, apiKey, err_8;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 9, , 10]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                provider = 'infura';
                key = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
                estimatedGas = void 0;
                return [4 /*yield*/, pool.mintManagerFee(null, true)];
            case 6:
                estimatedGas = _a.sent();
                console.log(estimatedGas);
                return [4 /*yield*/, (0, txFees_1.txFees)(network, provider, key, estimatedGas)];
            case 7:
                txOptions = _a.sent();
                return [4 /*yield*/, pool.mintManagerFee(txOptions, false)];
            case 8:
                tx = _a.sent();
                if (req.query.apiKey) {
                    apiKey = req.query.apiKey;
                    console.log("Sending API payment");
                    (0, txFees_1.apiPayment)(network, apiKey, tx, provider, key, null);
                }
                res.status(200).send({ status: "success", msg: tx });
                return [3 /*break*/, 10];
            case 9:
                err_8 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_8 });
                return [3 /*break*/, 10];
            case 10: return [2 /*return*/];
        }
    });
}); });
adminRouter.post("/changeAssets", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, apiKey, provider, key, tx, err_9;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 7, , 8]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
            case 5: return [4 /*yield*/, pool.changeAssets(req.body.assets)];
            case 6:
                tx = _a.sent();
                res.status(200).send({ status: "success", msg: tx.hash });
                return [3 /*break*/, 8];
            case 7:
                err_9 = _a.sent();
                res.status(400).send({ status: "fail", msg: err_9 });
                return [3 /*break*/, 8];
            case 8: return [2 /*return*/];
        }
    });
}); });
adminRouter.post("/setTrader", function (req, res) { return __awaiter(void 0, void 0, void 0, function () {
    var network, poolAddress, pool, dHedge, manager, apiKey, provider, key, tx, err_10;
    return __generator(this, function (_a) {
        switch (_a.label) {
            case 0:
                _a.trys.push([0, 7, , 8]);
                network = v2_sdk_1.Network.POLYGON;
                if (req.query.network)
                    network = req.query.network;
                poolAddress = req.query.pool;
                pool = void 0;
                dHedge = void 0;
                manager = null;
                if (req.query.manager) {
                    manager = req.query.manager;
                }
                if (!req.query.apiKey) return [3 /*break*/, 3];
                apiKey = req.query.apiKey;
                provider = null;
                key = null;
                if (req.query.provider) {
                    provider = req.query.provider;
                }
                if (req.query.providerKey) {
                    key = req.query.providerKey;
                }
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
            case 5: return [4 /*yield*/, pool.setTrader(req.body.traderAccount)];
            case 6:
                tx = _a.sent();
                res.status(200).send({ status: "success", status_code: 200, msg: tx.hash });
                return [3 /*break*/, 8];
            case 7:
                err_10 = _a.sent();
                res.status(400).send({ status: "fail", status_code: 400, msg: err_10 });
                return [3 /*break*/, 8];
            case 8: return [2 /*return*/];
        }
    });
}); });
exports.default = adminRouter;
