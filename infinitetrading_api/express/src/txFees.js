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
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.txFees = void 0;
exports.apiPayment = apiPayment;
var v2_sdk_1 = require("@dhedge/v2-sdk");
var rpc_1 = require("./rpc");
var walletv2_1 = require("./walletv2");
var axios_1 = require("axios");
require("dotenv").config({ path: '../.env' });
var DAO_GAS = process.env.DAO_GAS;
var MASTER_APIKEY = process.env.MASTER_APIKEY;
var GAS_MULTIPLIERS = {
    optimism: 20,
    base: 5,
    polygon: 15,
    arbitrum: 5,
    ethereum: 2,
    default: 10, // fallback if network not listed
};
var INFURA_API_KEY = process.env.INFURA_PROJECT_ID;
function getGasToken(network) {
    if (network == "polygon")
        return 'MATIC';
    return 'ETH';
}
var networkChainIdMap = (_a = {},
    _a[v2_sdk_1.Network.ETHEREUM] = 1,
    _a[v2_sdk_1.Network.POLYGON] = 137,
    _a[v2_sdk_1.Network.OPTIMISM] = 10,
    _a[v2_sdk_1.Network.ARBITRUM] = 42161,
    _a[v2_sdk_1.Network.BASE] = 8453,
    _a);
//type getFeeData = {
//  maxFeePerGas: ethers.BigNumber;
//  maxPriorityFeePerGas: ethers.BigNumber;
//}
//async function getFeeData(network: Network,provider: string | ethers.providers.Provider | null,key: string | null): Promise<getFeeData> {
//	try {
//		let rpc_provider: ethers.providers.Provider;
//                if (provider instanceof ethers.providers.Provider) rpc_provider = provider;
//                else rpc_provider = new ethers.providers.JsonRpcProvider(rpc(network, provider, key));
//    		return await rpc_provider.getFeeData();
//  	} catch (error) {
//		const error_msg = "Error fetching fee data: ${error}";
//    		console.error(error_msg);
//  		throw error_msg;
//  	}
//}
function estimateSendGas(provider, toAddress, value) {
    return __awaiter(this, void 0, void 0, function () {
        var gasLimit;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, provider.estimateGas({ to: toAddress, value: value })];
                case 1:
                    gasLimit = _a.sent();
                    return [2 /*return*/, gasLimit];
            }
        });
    });
}
function getGasPrice(network, provider, key) {
    return __awaiter(this, void 0, void 0, function () {
        var rpc_provider, gasPrice, gasPriceInGwei, error_1, error_msg;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 3, , 4]);
                    rpc_provider = void 0;
                    if (provider instanceof v2_sdk_1.ethers.providers.Provider)
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    return [4 /*yield*/, rpc_provider.getGasPrice()];
                case 1:
                    gasPrice = _a.sent();
                    return [4 /*yield*/, v2_sdk_1.ethers.utils.formatUnits(gasPrice, "gwei")];
                case 2:
                    gasPriceInGwei = _a.sent();
                    return [2 /*return*/, gasPriceInGwei];
                case 3:
                    error_1 = _a.sent();
                    error_msg = "Error fetching gas price: ".concat(String(error_1));
                    console.error(error_msg);
                    throw new Error(error_msg);
                case 4: return [2 /*return*/];
            }
        });
    });
}
function sleep(ms) { return new Promise(function (resolve) { return setTimeout(resolve, ms); }); }
var txFees = function (network, provider, key, estimatedGasLike) { return __awaiter(void 0, void 0, void 0, function () {
    var estBN, g, gasLimit, data, toGweiStr, maxPriorityFeePerGas, maxFeePerGas, chainId, data, maxPriorityFeePerGas, maxFeePerGas, err_1;
    var _a, _b;
    return __generator(this, function (_c) {
        switch (_c.label) {
            case 0:
                _c.trys.push([0, 5, , 6]);
                estBN = null;
                if (estimatedGasLike != null) {
                    if (typeof estimatedGasLike === "string" ||
                        typeof estimatedGasLike === "number" ||
                        typeof estimatedGasLike === "bigint") {
                        estBN = v2_sdk_1.ethers.BigNumber.from(estimatedGasLike.toString());
                    }
                    else if (v2_sdk_1.ethers.BigNumber.isBigNumber(estimatedGasLike)) {
                        estBN = estimatedGasLike;
                    }
                    else if (typeof estimatedGasLike === "object" &&
                        "gas" in estimatedGasLike &&
                        estimatedGasLike.gas != null) {
                        g = estimatedGasLike.gas;
                        estBN = v2_sdk_1.ethers.BigNumber.isBigNumber(g)
                            ? g
                            : v2_sdk_1.ethers.BigNumber.from(g.toString());
                    }
                }
                gasLimit = estBN ? estBN.mul(3).toString() : "10000000";
                if (!(network === v2_sdk_1.Network.POLYGON)) return [3 /*break*/, 2];
                return [4 /*yield*/, axios_1.default.get("https://gasstation.polygon.technology/v2")];
            case 1:
                data = (_c.sent()).data;
                toGweiStr = function (n) { return n.toFixed(9); };
                maxPriorityFeePerGas = v2_sdk_1.ethers.utils
                    .parseUnits(toGweiStr(((_a = data.fast.maxPriorityFee) !== null && _a !== void 0 ? _a : 0) * 1.1), "gwei")
                    .toString();
                maxFeePerGas = v2_sdk_1.ethers.utils
                    .parseUnits(toGweiStr(((_b = data.fast.maxFee) !== null && _b !== void 0 ? _b : 0) * 2), "gwei")
                    .toString();
                return [2 /*return*/, { gasLimit: gasLimit, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas, type: 2 }];
            case 2:
                chainId = networkChainIdMap[network];
                return [4 /*yield*/, axios_1.default.get("https://gas.api.infura.io/v3/".concat(INFURA_API_KEY, "/networks/").concat(chainId, "/suggestedGasFees"))];
            case 3:
                data = (_c.sent()).data;
                maxPriorityFeePerGas = v2_sdk_1.ethers.utils
                    .parseUnits(String(data.high.suggestedMaxPriorityFeePerGas), "gwei")
                    .toString();
                maxFeePerGas = v2_sdk_1.ethers.utils
                    .parseUnits(String(data.high.suggestedMaxFeePerGas), "gwei")
                    .toString();
                return [2 /*return*/, { gasLimit: gasLimit, maxPriorityFeePerGas: maxPriorityFeePerGas, maxFeePerGas: maxFeePerGas, type: 2 }];
            case 4: return [3 /*break*/, 6];
            case 5:
                err_1 = _c.sent();
                console.error("txFees error:", err_1);
                throw (err_1 instanceof Error ? err_1 : new Error(String(err_1)));
            case 6: return [2 /*return*/];
        }
    });
}); };
exports.txFees = txFees;
// Start with your parameters
//gas_limit = 420000
//base_fee_per_gas = 0.05 gwei
//priority_fee_per_gas = 0.1 gwei
// Max fee per gas is the sum of the base fee and the priority fee
//max_fee_per_gas = base_fee_per_gas + priority_fee_per_gas = 0.15 gwei
// Execution gas fee is the product of the gas limit and the max fee per gas
//execution_gas_fee = gas_limit * max_fee_per_gas = 420000 * 0.15 gwei = 0.000063 ETH
function sendTransaction(network, apiKey, toAddress, value, // ETH-denominated decimal string
provider, key, ethers_wallet, balance) {
    return __awaiter(this, void 0, void 0, function () {
        var isProviderLike, assertEthDecimal, wallet, rpc_provider, parsedValue, gasLimit, feeData, maxPriorityFeePerGas, maxFeePerGas, totalGasCost, totalCost, gasToken, tx, sentTx, err_2;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    isProviderLike = function (p) {
                        return !!p && typeof p.getNetwork === "function";
                    };
                    assertEthDecimal = function (s) {
                        if (!/^(0|[1-9]\d*)(\.\d{1,18})?$/.test(s)) {
                            throw new Error("Invalid ETH decimal string (no scientific notation, max 18 dp): \"".concat(s, "\""));
                        }
                    };
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 9, , 10]);
                    console.log("Entering sendTransaction function");
                    wallet = void 0;
                    if (!(ethers_wallet == null)) return [3 /*break*/, 3];
                    return [4 /*yield*/, (0, walletv2_1.walletv2)(network, apiKey, provider, key)];
                case 2:
                    wallet = _a.sent();
                    return [3 /*break*/, 4];
                case 3:
                    wallet = ethers_wallet;
                    _a.label = 4;
                case 4:
                    rpc_provider = void 0;
                    if (isProviderLike(provider))
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    // 1) Validate & parse value (ETH string -> wei BigNumber)
                    assertEthDecimal(value);
                    parsedValue = v2_sdk_1.ethers.utils.parseEther(value);
                    gasLimit = v2_sdk_1.ethers.BigNumber.from(500000);
                    if (!(balance == null)) return [3 /*break*/, 6];
                    return [4 /*yield*/, rpc_provider.getBalance(wallet.address)];
                case 5:
                    balance = _a.sent();
                    _a.label = 6;
                case 6: return [4 /*yield*/, (0, exports.txFees)(network, rpc_provider, key, gasLimit.toString())];
                case 7:
                    feeData = _a.sent();
                    maxPriorityFeePerGas = v2_sdk_1.ethers.BigNumber.from(feeData.maxPriorityFeePerGas);
                    maxFeePerGas = v2_sdk_1.ethers.BigNumber.from(feeData.maxFeePerGas);
                    totalGasCost = gasLimit.mul(maxFeePerGas);
                    totalCost = parsedValue.add(totalGasCost);
                    gasToken = getGasToken(network);
                    console.log("Sending payment transaction");
                    console.log("Address: ".concat(wallet.address, " Network: ").concat(network, " ") +
                        "Balance: ".concat(v2_sdk_1.ethers.utils.formatEther(balance), " ").concat(gasToken, " ") +
                        "Payment amount: ".concat(v2_sdk_1.ethers.utils.formatUnits(parsedValue, 18), " ").concat(gasToken));
                    console.log("Total Cost: ".concat(v2_sdk_1.ethers.utils.formatUnits(totalCost, 18), " ").concat(gasToken));
                    if (balance.lt(totalCost)) {
                        throw new Error("Insufficient funds for API Payment and Transaction cost");
                    }
                    tx = {
                        to: toAddress,
                        value: parsedValue,
                        gasLimit: gasLimit,
                        maxPriorityFeePerGas: maxPriorityFeePerGas,
                        maxFeePerGas: maxFeePerGas,
                        type: 2, // EIP-1559
                    };
                    return [4 /*yield*/, wallet.sendTransaction(tx)];
                case 8:
                    sentTx = _a.sent();
                    console.log("API Payment sent:", sentTx.hash);
                    return [2 /*return*/, sentTx];
                case 9:
                    err_2 = _a.sent();
                    console.error("sendTransaction error:", err_2);
                    throw err_2;
                case 10: return [2 /*return*/];
            }
        });
    });
}
function waitForReceiptWithTimeout(tx, timeout, provider) {
    return __awaiter(this, void 0, void 0, function () {
        return __generator(this, function (_a) {
            if (typeof tx === "string") {
                // If tx is a hash, wait for the receipt using the provider
                return [2 /*return*/, Promise.race([
                        provider.waitForTransaction(tx, 1, timeout).catch(function () {
                            throw new Error("Transaction receipt timeout");
                        }),
                    ])];
            }
            else if (typeof tx.wait === "function") {
                // If tx is a transaction response, use tx.wait
                return [2 /*return*/, Promise.race([
                        tx.wait(),
                        new Promise(function (_, reject) { return setTimeout(function () { return reject(new Error("Transaction receipt timeout")); }, timeout); }),
                    ])];
            }
            else {
                throw new Error("Invalid transaction object");
            }
            return [2 /*return*/];
        });
    });
}
function apiPayment(network, apiKey, tx, provider, key, ethers_wallet) {
    return __awaiter(this, void 0, void 0, function () {
        var wallet, rpc_provider, receipt, txHash, gasToken, tx_new, receipt_new, gasUsed, gasPrice, gasCost, gasCostInEther, multiplierX, multiplier, multipliedCost, apiFee, apiFeeInEther, balance, response, error_2, error_3;
        var _a, _b, _c, _d;
        return __generator(this, function (_e) {
            switch (_e.label) {
                case 0:
                    _e.trys.push([0, 12, , 13]);
                    console.log("Entering apiPayment function");
                    wallet = void 0;
                    if (!(ethers_wallet == null)) return [3 /*break*/, 2];
                    return [4 /*yield*/, (0, walletv2_1.walletv2)(network, apiKey, provider, key)];
                case 1:
                    wallet = _e.sent();
                    return [3 /*break*/, 3];
                case 2:
                    wallet = ethers_wallet;
                    _e.label = 3;
                case 3:
                    rpc_provider = void 0;
                    if (provider instanceof v2_sdk_1.ethers.providers.Provider)
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    return [4 /*yield*/, waitForReceiptWithTimeout(tx, 20000, rpc_provider).catch(function (error) { throw new Error(error); })
                        //const receipt = await tx.wait();
                    ];
                case 4:
                    receipt = _e.sent();
                    //const receipt = await tx.wait();
                    console.log('Transaction mined:', receipt);
                    txHash = tx.hash;
                    gasToken = getGasToken(network);
                    return [4 /*yield*/, rpc_provider.getTransaction(txHash)];
                case 5:
                    tx_new = _e.sent();
                    if (!tx_new)
                        throw new Error('Transaction not found');
                    return [4 /*yield*/, rpc_provider.getTransactionReceipt(txHash)];
                case 6:
                    receipt_new = _e.sent();
                    if (!receipt_new)
                        throw new Error('Transaction failed, no API PAYMENT');
                    gasUsed = receipt_new.gasUsed;
                    console.log("Gas Used: ".concat(gasUsed.toString()));
                    gasPrice = (_c = (_b = (_a = receipt_new.effectiveGasPrice) !== null && _a !== void 0 ? _a : tx_new.gasPrice) !== null && _b !== void 0 ? _b : tx_new.maxFeePerGas) !== null && _c !== void 0 ? _c : v2_sdk_1.ethers.BigNumber.from(0);
                    console.log("Gas Price: ".concat(v2_sdk_1.ethers.utils.formatUnits(gasPrice, 'gwei'), " gwei"));
                    gasCost = gasUsed.mul(gasPrice);
                    gasCostInEther = v2_sdk_1.ethers.utils.formatUnits(gasCost, 18);
                    console.log("Gas Cost: ".concat(gasCostInEther, " ").concat(gasToken));
                    multiplierX = (_d = GAS_MULTIPLIERS[network]) !== null && _d !== void 0 ? _d : 10;
                    multiplier = v2_sdk_1.ethers.BigNumber.from(Math.floor(multiplierX * 100));
                    multipliedCost = gasCost.mul(multiplier);
                    apiFee = multipliedCost.div(100);
                    apiFeeInEther = v2_sdk_1.ethers.utils.formatUnits(apiFee, 18);
                    console.log("API Fee: ".concat(apiFeeInEther, " ").concat(gasToken));
                    return [4 /*yield*/, wallet.getBalance()];
                case 7:
                    balance = _e.sent();
                    console.log("Customer Wallet Balance: ".concat(v2_sdk_1.ethers.utils.formatEther(balance), " ").concat(gasToken));
                    if (balance.lt(apiFee)) {
                        throw new Error("Insufficient Customer Balance for API Payment: ".concat(v2_sdk_1.ethers.utils.formatEther(balance), ", API Fee: ").concat(apiFeeInEther));
                    }
                    _e.label = 8;
                case 8:
                    _e.trys.push([8, 10, , 11]);
                    return [4 /*yield*/, sendTransaction(network, apiKey, DAO_GAS, apiFeeInEther, rpc_provider, null, wallet, balance)];
                case 9:
                    response = _e.sent();
                    return [3 /*break*/, 11];
                case 10:
                    error_2 = _e.sent();
                    console.error('Error', error_2);
                    return [3 /*break*/, 11];
                case 11: return [3 /*break*/, 13];
                case 12:
                    error_3 = _e.sent();
                    console.error('Error:', error_3);
                    return [3 /*break*/, 13];
                case 13: return [2 /*return*/];
            }
        });
    });
}
//async function processPayments(network: Network, apiKey: string, provider: string | ethers.providers.Provider | null, key: string | null,ethers_wallet: ethers.Wallet | null,transactions: string | string[]): Promise<void> {
//    if (typeof transactions === 'string') {
//        await processTransaction(transactions);
//    } else if (Array.isArray(transactions)) {
//        for (const transaction of transactions) {
//            await processTransaction(transaction);
//        }
//    } else {
//        throw new TypeError('transactions must be a string or an array of strings');
//    }
//}
function clearPendingTransactions(network, provider, apiKey, key, ethers_wallet) {
    return __awaiter(this, void 0, void 0, function () {
        var rpc_provider, wallet, nonce, newTransaction, txResponse, error_4;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 7, , 8]);
                    rpc_provider = void 0;
                    if (provider instanceof v2_sdk_1.ethers.providers.Provider)
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    wallet = void 0;
                    if (!(ethers_wallet == null)) return [3 /*break*/, 2];
                    return [4 /*yield*/, (0, walletv2_1.walletv2)(network, apiKey, provider, key)];
                case 1:
                    wallet = _a.sent();
                    return [3 /*break*/, 3];
                case 2:
                    wallet = ethers_wallet;
                    _a.label = 3;
                case 3: return [4 /*yield*/, wallet.getTransactionCount("pending")];
                case 4:
                    nonce = _a.sent();
                    console.log(nonce);
                    newTransaction = {
                        to: wallet.address,
                        value: v2_sdk_1.ethers.utils.parseEther("0.0"), // Send 0 ETH
                        nonce: nonce,
                        gasLimit: v2_sdk_1.ethers.utils.hexlify(21000), // Standard gas limit for simple transfers
                        maxPriorityFeePerGas: v2_sdk_1.ethers.utils.parseUnits('3.0', 'gwei'), // Higher priority fee
                        maxFeePerGas: v2_sdk_1.ethers.utils.parseUnits('50.0', 'gwei'), // Higher fee
                    };
                    return [4 /*yield*/, wallet.sendTransaction(newTransaction)];
                case 5:
                    txResponse = _a.sent();
                    console.log("Transaction sent: ".concat(txResponse.hash));
                    // Wait for the transaction to be mined
                    return [4 /*yield*/, txResponse.wait()];
                case 6:
                    // Wait for the transaction to be mined
                    _a.sent();
                    console.log("Transaction mined: ".concat(txResponse.hash));
                    return [3 /*break*/, 8];
                case 7:
                    error_4 = _a.sent();
                    console.error("Error clearing pending transactions: ".concat(error_4));
                    throw error_4;
                case 8: return [2 /*return*/];
            }
        });
    });
}
function displayStats(network, provider, key) {
    return __awaiter(this, void 0, void 0, function () {
        var rpc_provider, gasPrice, error_5, feedata, mpfpg_gwei, mfpg_gwei, mpfpg_wei, mfpg_wei;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    console.log("Fee data for ".concat(network, " and provider: ").concat(provider));
                    if (provider instanceof v2_sdk_1.ethers.providers.Provider)
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 3, , 4]);
                    return [4 /*yield*/, getGasPrice(network, rpc_provider, key)];
                case 2:
                    gasPrice = _a.sent();
                    console.log("Current gas price: ".concat(gasPrice, " Gwei"));
                    return [3 /*break*/, 4];
                case 3:
                    error_5 = _a.sent();
                    console.log("Failed to fetch gas price for ".concat(network, ":"), error_5);
                    return [3 /*break*/, 4];
                case 4: return [4 /*yield*/, (0, exports.txFees)(network, rpc_provider, key, '0x02b665')];
                case 5:
                    feedata = _a.sent();
                    mpfpg_gwei = v2_sdk_1.ethers.utils.formatUnits(feedata.maxPriorityFeePerGas, "gwei");
                    mfpg_gwei = v2_sdk_1.ethers.utils.formatUnits(feedata.maxFeePerGas, "gwei");
                    mpfpg_wei = v2_sdk_1.ethers.utils.formatUnits(feedata.maxPriorityFeePerGas, "wei");
                    mfpg_wei = v2_sdk_1.ethers.utils.formatUnits(feedata.maxFeePerGas, "wei");
                    console.log("---------------");
                    console.log("Max Priority Fee Per Gas in GWEI: ".concat(mpfpg_gwei));
                    console.log("Max fee per gas in GWEI: ".concat(mfpg_gwei));
                    console.log("---------------");
                    console.log("Max Priority Fee Per Gas in WEI: ".concat(mpfpg_wei));
                    console.log("Max fee per gas in WEI: ".concat(mfpg_wei));
                    console.log("---------------");
                    console.log(feedata);
                    return [2 /*return*/];
            }
        });
    });
}
function display() {
    return __awaiter(this, void 0, void 0, function () {
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, displayStats(v2_sdk_1.Network.POLYGON, 'infura', null)
                    //const network = 'ethereum' as Network;
                    //displayStats(network,'infura',null)
                ];
                case 1:
                    _a.sent();
                    //const network = 'ethereum' as Network;
                    //displayStats(network,'infura',null)
                    return [4 /*yield*/, displayStats(v2_sdk_1.Network.ARBITRUM, 'infura', null)
                        //displayStats(Network.BASE,'infura',null)
                    ];
                case 2:
                    //const network = 'ethereum' as Network;
                    //displayStats(network,'infura',null)
                    _a.sent();
                    //displayStats(Network.BASE,'infura',null)
                    return [4 /*yield*/, displayStats(v2_sdk_1.Network.OPTIMISM, 'infura', null)
                        //console.log('Original DHEDGE TX FEES')
                        //const optx = await getTxOptions(Network.POLYGON,'infura',null);
                        //console.log(optx)
                    ];
                case 3:
                    //displayStats(Network.BASE,'infura',null)
                    _a.sent();
                    return [2 /*return*/];
            }
        });
    });
}
//display()
